# AIOS Linux v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootable Linux "AI OS": Fedora + provisioner boots straight into a full-screen AI chat shell that launches apps, manages files, and answers questions via local Ollama.

**Architecture:** Python daemon (`aios_daemon`, FastAPI) serves a static web chat UI and a WebSocket; an AgentLoop streams from Ollama and dispatches tool calls through a registry. systemd units run Ollama, the daemon, and a cage+Chromium kiosk. `provision.sh` converts stock Fedora Minimal into AIOS. All agent logic is OS-agnostic and unit-tested on macOS; the OS pieces are exercised in an aarch64 VM.

**Tech Stack:** Python 3.11+, FastAPI, uvicorn, httpx, pytest + pytest-asyncio, vanilla JS web UI, cage, Chromium, Ollama (qwen2.5:7b VM / 14b bare metal), systemd, Fedora Minimal 42.

**Dev prerequisites (macOS):** `python3 --version` ≥ 3.11.

---

### Task 1: Repo reorg + daemon scaffold

**Files:**
- Move: `Package.swift`, `Package.resolved`, `Sources/`, `Tests/` → `macos/`
- Create: `os/daemon/pyproject.toml`
- Create: `os/daemon/aios_daemon/__init__.py`
- Create: `os/daemon/aios_daemon/config.py`
- Create: `os/daemon/tests/test_config.py`

- [ ] **Step 1: Move Swift app into macos/**

```bash
mkdir macos
git mv Package.swift Package.resolved Sources Tests macos/
git mv README.md macos/README.md
git commit -m "chore: move Swift macOS shell into macos/ ahead of Linux OS work"
```

- [ ] **Step 2: Create daemon package files**

`os/daemon/pyproject.toml`:
```toml
[project]
name = "aios-daemon"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.115",
    "uvicorn>=0.30",
    "httpx>=0.27",
    "websockets>=13.0",
]

[project.optional-dependencies]
dev = ["pytest>=8.0", "pytest-asyncio>=0.24"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
markers = ["live: requires running Ollama with the configured model"]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools]
packages = ["aios_daemon"]
```

`os/daemon/aios_daemon/__init__.py`: empty file.

`os/daemon/aios_daemon/config.py`:
```python
import os
from dataclasses import dataclass, field


@dataclass
class Config:
    ollama_url: str = field(default_factory=lambda: os.environ.get("AIOS_OLLAMA_URL", "http://localhost:11434"))
    model: str = field(default_factory=lambda: os.environ.get("AIOS_MODEL", "qwen2.5:7b"))
    port: int = field(default_factory=lambda: int(os.environ.get("AIOS_PORT", "8800")))
    search_root: str = field(default_factory=lambda: os.environ.get("AIOS_SEARCH_ROOT", os.path.expanduser("~")))
```

`os/daemon/tests/test_config.py`:
```python
from aios_daemon.config import Config


def test_defaults():
    cfg = Config()
    assert cfg.model == "qwen2.5:7b"
    assert cfg.port == 8800
    assert cfg.ollama_url.startswith("http://")


def test_env_overrides(monkeypatch):
    monkeypatch.setenv("AIOS_MODEL", "qwen2.5:14b")
    monkeypatch.setenv("AIOS_PORT", "9000")
    cfg = Config()
    assert cfg.model == "qwen2.5:14b"
    assert cfg.port == 9000
```

- [ ] **Step 3: Create venv, install, run tests**

```bash
cd os/daemon
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
.venv/bin/pytest -q
```
Expected: 2 passed.

- [ ] **Step 4: Add .gitignore entry and commit**

Append to repo-root `.gitignore`:
```
.venv/
__pycache__/
*.egg-info/
```

```bash
git add os/daemon .gitignore
git commit -m "feat: scaffold aios-daemon Python package with config"
```

---

### Task 2: ToolRegistry + sys_info + file_ops

**Files:**
- Create: `os/daemon/aios_daemon/tools.py`
- Create: `os/daemon/tests/test_tools.py`

All commands below run from `os/daemon/` with `.venv/bin/pytest`.

- [ ] **Step 1: Write failing tests**

`os/daemon/tests/test_tools.py`:
```python
import subprocess
from pathlib import Path

import pytest

from aios_daemon.tools import FileOps, SysInfo, ToolRegistry


# --- registry ---

class EchoTool:
    spec = {
        "name": "echo",
        "description": "Echoes input",
        "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
    }

    async def execute(self, args):
        return f"echo: {args.get('text', '')}"


class BoomTool:
    spec = {"name": "boom", "description": "Always fails", "parameters": {"type": "object", "properties": {}}}

    async def execute(self, args):
        raise RuntimeError("boom")


async def test_registry_dispatches():
    reg = ToolRegistry([EchoTool()])
    assert await reg.execute("echo", {"text": "hi"}) == "echo: hi"


async def test_registry_unknown_tool():
    reg = ToolRegistry([])
    assert "unknown tool" in await reg.execute("nope", {})


async def test_registry_tool_error_as_string():
    reg = ToolRegistry([BoomTool()])
    assert "boom" in await reg.execute("boom", {})


def test_registry_specs_ollama_format():
    reg = ToolRegistry([EchoTool()])
    assert reg.specs == [{
        "type": "function",
        "function": {
            "name": "echo",
            "description": "Echoes input",
            "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
        },
    }]


# --- sys_info ---

async def test_sys_info_reports_keys():
    out = await SysInfo().execute({})
    assert "time:" in out
    assert "disk_free:" in out
    assert "memory_total:" in out


# --- file_ops ---

@pytest.fixture
def tmp_home(tmp_path):
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "resume.pdf").write_text("x")
    (tmp_path / "notes.txt").write_text("y")
    return tmp_path


async def test_search_finds_by_substring(tmp_home):
    ops = FileOps(search_root=str(tmp_home))
    out = await ops.execute({"action": "search", "query": "resume"})
    assert "resume.pdf" in out


async def test_search_no_results(tmp_home):
    ops = FileOps(search_root=str(tmp_home))
    out = await ops.execute({"action": "search", "query": "zzz-none"})
    assert "No files found" in out


async def test_move(tmp_home):
    ops = FileOps(search_root=str(tmp_home))
    src = tmp_home / "notes.txt"
    dst = tmp_home / "docs" / "notes.txt"
    out = await ops.execute({"action": "move", "path": str(src), "destination": str(dst)})
    assert "Moved" in out
    assert not src.exists()
    assert dst.exists()


async def test_trash_uses_gio(tmp_home, monkeypatch):
    calls = []

    def fake_run(cmd, **kwargs):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout=b"", stderr=b"")

    monkeypatch.setattr(subprocess, "run", fake_run)
    ops = FileOps(search_root=str(tmp_home))
    out = await ops.execute({"action": "trash", "path": str(tmp_home / "notes.txt")})
    assert "Trashed" in out
    assert calls[0][:2] == ["gio", "trash"]


async def test_missing_action(tmp_home):
    ops = FileOps(search_root=str(tmp_home))
    out = await ops.execute({})
    assert "Error" in out and "action" in out
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest tests/test_tools.py -q`
Expected: FAIL — ImportError (tools module missing).

- [ ] **Step 3: Implement**

`os/daemon/aios_daemon/tools.py`:
```python
import asyncio
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

SEARCH_CAP = 20


class ToolRegistry:
    def __init__(self, tools):
        self._tools = {t.spec["name"]: t for t in tools}

    @property
    def specs(self):
        return [{"type": "function", "function": t.spec} for t in self._tools.values()]

    async def execute(self, name, args):
        tool = self._tools.get(name)
        if tool is None:
            return f"Error: unknown tool '{name}'"
        try:
            return await tool.execute(args)
        except Exception as e:  # tool errors feed back to the model as strings
            return f"Error: {e}"


class SysInfo:
    spec = {
        "name": "sys_info",
        "description": "Report system status: current time, free disk space, total memory, uptime.",
        "parameters": {"type": "object", "properties": {}},
    }

    async def execute(self, args):
        disk = shutil.disk_usage("/")
        mem_bytes = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
        try:
            uptime = f"{float(Path('/proc/uptime').read_text().split()[0]) / 3600:.1f}h"
        except OSError:
            uptime = "n/a"
        return (
            f"time: {datetime.now().isoformat(timespec='seconds')}, "
            f"disk_free: {disk.free // 2**30}GiB of {disk.total // 2**30}GiB, "
            f"memory_total: {mem_bytes // 2**30}GiB, "
            f"uptime: {uptime}"
        )


class FileOps:
    spec = {
        "name": "file_ops",
        "description": (
            "File operations: search files by name substring, open a file, move a file, "
            "or put a file in the Trash. Never permanently deletes."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ["search", "open", "move", "trash"]},
                "query": {"type": "string", "description": "Filename substring for search"},
                "path": {"type": "string", "description": "Absolute path for open/move/trash"},
                "destination": {"type": "string", "description": "Absolute destination for move"},
            },
            "required": ["action"],
        },
    }

    def __init__(self, search_root):
        self.search_root = search_root

    async def execute(self, args):
        action = args.get("action")
        if not action:
            return "Error: missing 'action'"
        if action == "search":
            query = args.get("query")
            if not query:
                return "Error: search requires 'query'"
            return await asyncio.to_thread(self._search, query)
        if action == "open":
            path = args.get("path")
            if not path:
                return "Error: missing 'path'"
            subprocess.Popen(["xdg-open", path])
            return f"Opened {path}"
        if action == "move":
            path, dest = args.get("path"), args.get("destination")
            if not path or not dest:
                return "Error: move requires 'path' and 'destination'"
            shutil.move(path, dest)
            return f"Moved {path} -> {dest}"
        if action == "trash":
            path = args.get("path")
            if not path:
                return "Error: missing 'path'"
            result = subprocess.run(["gio", "trash", path], capture_output=True)
            if result.returncode != 0:
                return f"Error: {result.stderr.decode().strip() or 'trash failed'}"
            return f"Trashed {path}"
        return f"Error: unknown action '{action}'"

    def _search(self, query):
        q = query.lower()
        hits = []
        for root, dirs, files in os.walk(self.search_root):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for f in files:
                if q in f.lower():
                    hits.append(str(Path(root) / f))
                    if len(hits) >= SEARCH_CAP:
                        return "\n".join(hits)
        return "\n".join(hits) if hits else f"No files found for '{query}'"
```

- [ ] **Step 4: Run to verify pass**

Run: `.venv/bin/pytest tests/test_tools.py -q`
Expected: 10 passed.

- [ ] **Step 5: Commit**

```bash
git add aios_daemon/tools.py tests/test_tools.py
git commit -m "feat: add ToolRegistry, sys_info, and file_ops tools"
```

---

### Task 3: app_launch tool

**Files:**
- Modify: `os/daemon/aios_daemon/tools.py` (append class)
- Modify: `os/daemon/tests/test_tools.py` (append tests)

- [ ] **Step 1: Append failing tests to test_tools.py**

```python
# --- app_launch ---

from aios_daemon.tools import AppLaunch


@pytest.fixture
def apps_dir(tmp_path):
    d = tmp_path / "applications"
    d.mkdir()
    (d / "org.gnome.TextEditor.desktop").write_text(
        "[Desktop Entry]\nName=Text Editor\nExec=gnome-text-editor %U\nType=Application\n"
    )
    (d / "firefox.desktop").write_text(
        "[Desktop Entry]\nName=Firefox\nExec=firefox %u\nType=Application\n"
    )
    return d


async def test_launch_matches_by_name(apps_dir, monkeypatch):
    calls = []

    def fake_popen(cmd, **kwargs):
        calls.append(cmd)

    monkeypatch.setattr(subprocess, "Popen", fake_popen)
    tool = AppLaunch(apps_dirs=[str(apps_dir)])
    out = await tool.execute({"name": "text editor"})
    assert "Launched" in out
    assert calls[0] == ["gtk-launch", "org.gnome.TextEditor"]


async def test_launch_unknown_app(apps_dir):
    tool = AppLaunch(apps_dirs=[str(apps_dir)])
    out = await tool.execute({"name": "photoshop"})
    assert "Error" in out


async def test_launch_lists_apps(apps_dir):
    tool = AppLaunch(apps_dirs=[str(apps_dir)])
    out = await tool.execute({"action": "list"})
    assert "Firefox" in out and "Text Editor" in out
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest tests/test_tools.py -q`
Expected: FAIL — ImportError: cannot import name 'AppLaunch'.

- [ ] **Step 3: Append implementation to tools.py**

```python
class AppLaunch:
    spec = {
        "name": "app_launch",
        "description": "Launch an installed application by name, or list installed applications.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Application name, e.g. 'Firefox'"},
                "action": {"type": "string", "enum": ["launch", "list"], "description": "Defaults to launch"},
            },
        },
    }

    DEFAULT_DIRS = ["/usr/share/applications", os.path.expanduser("~/.local/share/applications")]

    def __init__(self, apps_dirs=None):
        self.apps_dirs = apps_dirs or self.DEFAULT_DIRS

    def _installed(self):
        apps = {}  # display name -> desktop id
        for d in self.apps_dirs:
            for entry in sorted(Path(d).glob("*.desktop")) if Path(d).is_dir() else []:
                name = None
                for line in entry.read_text(errors="ignore").splitlines():
                    if line.startswith("Name=") and name is None:
                        name = line[5:].strip()
                if name:
                    apps[name] = entry.stem
        return apps

    async def execute(self, args):
        apps = await asyncio.to_thread(self._installed)
        if args.get("action") == "list":
            return ", ".join(sorted(apps)) or "No applications found"
        name = args.get("name")
        if not name:
            return "Error: missing 'name'"
        wanted = name.lower()
        for display, desktop_id in apps.items():
            if wanted in display.lower():
                subprocess.Popen(["gtk-launch", desktop_id])
                return f"Launched {display}"
        return f"Error: no installed app matches '{name}'"
```

- [ ] **Step 4: Run to verify pass**

Run: `.venv/bin/pytest tests/test_tools.py -q`
Expected: 13 passed.

- [ ] **Step 5: Commit**

```bash
git add aios_daemon/tools.py tests/test_tools.py
git commit -m "feat: add app_launch tool with .desktop discovery"
```

---

### Task 4: OllamaClient

**Files:**
- Create: `os/daemon/aios_daemon/ollama.py`
- Create: `os/daemon/tests/test_ollama.py`

Ollama `/api/chat` streams NDJSON lines `{"message":{"role":"assistant","content":"tok","tool_calls":[...]},"done":false}`; tool calls arrive whole in one chunk with shape `{"function":{"name":"x","arguments":{...}}}`.

- [ ] **Step 1: Write failing tests**

`os/daemon/tests/test_ollama.py`:
```python
import json

import httpx

from aios_daemon.ollama import OllamaClient


def make_client(ndjson_body, captured):
    def handler(request):
        captured.append(json.loads(request.content))
        return httpx.Response(200, content=ndjson_body.encode())

    transport = httpx.MockTransport(handler)
    http = httpx.AsyncClient(transport=transport, base_url="http://test")
    return OllamaClient(base_url="http://test", model="qwen2.5:7b", http=http)


async def test_streams_tokens_and_content():
    body = (
        '{"message":{"role":"assistant","content":"Hel"},"done":false}\n'
        '{"message":{"role":"assistant","content":"lo"},"done":false}\n'
        '{"message":{"role":"assistant","content":""},"done":true}\n'
    )
    captured, tokens = [], []

    async def on_token(t):
        tokens.append(t)

    client = make_client(body, captured)
    reply = await client.chat([{"role": "user", "content": "hi"}], tools=[], on_token=on_token)
    assert reply["content"] == "Hello"
    assert tokens == ["Hel", "lo"]
    assert reply.get("tool_calls") in (None, [])


async def test_parses_tool_calls():
    body = (
        '{"message":{"role":"assistant","content":"","tool_calls":'
        '[{"function":{"name":"app_launch","arguments":{"name":"Firefox"}}}]},"done":true}\n'
    )
    captured = []

    async def on_token(t):
        pass

    client = make_client(body, captured)
    reply = await client.chat([{"role": "user", "content": "open firefox"}], tools=[], on_token=on_token)
    assert reply["tool_calls"][0]["function"]["name"] == "app_launch"
    assert reply["tool_calls"][0]["function"]["arguments"] == {"name": "Firefox"}


async def test_sends_model_messages_and_tools():
    body = '{"message":{"role":"assistant","content":"ok"},"done":true}\n'
    captured = []

    async def on_token(t):
        pass

    client = make_client(body, captured)
    spec = [{"type": "function", "function": {"name": "echo", "description": "d", "parameters": {}}}]
    await client.chat([{"role": "user", "content": "x"}], tools=spec, on_token=on_token)
    sent = captured[0]
    assert sent["model"] == "qwen2.5:7b"
    assert sent["stream"] is True
    assert sent["tools"] == spec
    assert sent["messages"][-1]["content"] == "x"


async def test_health_true_when_model_present():
    def handler(request):
        return httpx.Response(200, json={"models": [{"name": "qwen2.5:7b"}]})

    http = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://test")
    client = OllamaClient(base_url="http://test", model="qwen2.5:7b", http=http)
    assert await client.health() is True


async def test_health_false_when_down():
    def handler(request):
        raise httpx.ConnectError("refused")

    http = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://test")
    client = OllamaClient(base_url="http://test", model="qwen2.5:7b", http=http)
    assert await client.health() is False
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest tests/test_ollama.py -q`
Expected: FAIL — ImportError.

- [ ] **Step 3: Implement**

`os/daemon/aios_daemon/ollama.py`:
```python
import json

import httpx


class OllamaClient:
    def __init__(self, base_url, model, http=None):
        self.model = model
        # Cold model load can take minutes; generous read timeout.
        self.http = http or httpx.AsyncClient(base_url=base_url, timeout=httpx.Timeout(10, read=300))

    async def chat(self, messages, tools, on_token):
        payload = {"model": self.model, "stream": True, "messages": messages}
        if tools:
            payload["tools"] = tools
        content, tool_calls = "", []
        async with self.http.stream("POST", "/api/chat", json=payload) as response:
            response.raise_for_status()
            async for line in response.aiter_lines():
                if not line.strip():
                    continue
                chunk = json.loads(line)
                message = chunk.get("message") or {}
                token = message.get("content", "")
                if token:
                    content += token
                    await on_token(token)
                tool_calls.extend(message.get("tool_calls") or [])
                if chunk.get("done"):
                    break
        reply = {"role": "assistant", "content": content}
        if tool_calls:
            reply["tool_calls"] = tool_calls
        return reply

    async def health(self):
        try:
            response = await self.http.get("/api/tags", timeout=2)
        except httpx.HTTPError:
            return False
        if response.status_code != 200:
            return False
        names = [m.get("name", "") for m in response.json().get("models", [])]
        base = self.model.split(":")[0]
        return any(n.startswith(base) for n in names)
```

- [ ] **Step 4: Run to verify pass**

Run: `.venv/bin/pytest tests/test_ollama.py -q`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add aios_daemon/ollama.py tests/test_ollama.py
git commit -m "feat: add async streaming OllamaClient with health check"
```

---

### Task 5: AgentLoop

**Files:**
- Create: `os/daemon/aios_daemon/agent.py`
- Create: `os/daemon/tests/test_agent.py`

- [ ] **Step 1: Write failing tests**

`os/daemon/tests/test_agent.py`:
```python
from aios_daemon.agent import AgentLoop
from aios_daemon.tools import ToolRegistry


class EchoTool:
    spec = {
        "name": "echo",
        "description": "Echoes input",
        "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
    }

    async def execute(self, args):
        return f"echo: {args.get('text', '')}"


class MockLLM:
    def __init__(self, replies):
        self.replies = list(replies)
        self.received = []

    async def chat(self, messages, tools, on_token):
        self.received.append(list(messages))
        reply = self.replies.pop(0)
        if reply.get("content"):
            await on_token(reply["content"])
        return reply


class Collector:
    def __init__(self):
        self.events = []

    async def __call__(self, event):
        self.events.append(event)


async def test_plain_answer():
    llm = MockLLM([{"role": "assistant", "content": "Paris"}])
    loop = AgentLoop(llm=llm, registry=ToolRegistry([]))
    emit = Collector()
    await loop.run_turn("capital of France?", emit)
    kinds = [e["event"] for e in emit.events]
    assert "token" in kinds
    assert emit.events[-1] == {"event": "done", "text": "Paris"}


async def test_tool_loop_executes_and_feeds_back():
    call = {"function": {"name": "echo", "arguments": {"text": "hi"}}}
    llm = MockLLM([
        {"role": "assistant", "content": "", "tool_calls": [call]},
        {"role": "assistant", "content": "Done: echo: hi"},
    ])
    loop = AgentLoop(llm=llm, registry=ToolRegistry([EchoTool()]))
    emit = Collector()
    await loop.run_turn("say hi", emit)
    assert {"event": "tool", "name": "echo"} in emit.events
    assert emit.events[-1] == {"event": "done", "text": "Done: echo: hi"}
    # second LLM call saw the tool result
    assert any(m["role"] == "tool" and m["content"] == "echo: hi" for m in llm.received[1])


async def test_hop_limit():
    call = {"function": {"name": "echo", "arguments": {"text": "x"}}}
    looping = {"role": "assistant", "content": "", "tool_calls": [call]}
    llm = MockLLM([dict(looping) for _ in range(10)])
    loop = AgentLoop(llm=llm, registry=ToolRegistry([EchoTool()]))
    emit = Collector()
    await loop.run_turn("loop", emit)
    assert len(llm.received) <= 5
    assert emit.events[-1]["event"] == "done"


async def test_llm_error_emits_error_event():
    class FailingLLM:
        async def chat(self, messages, tools, on_token):
            raise ConnectionError("connection refused")

    loop = AgentLoop(llm=FailingLLM(), registry=ToolRegistry([]))
    emit = Collector()
    await loop.run_turn("hello", emit)
    assert emit.events[-1]["event"] == "error"
    assert "connection refused" in emit.events[-1]["text"]


async def test_history_persists_across_turns():
    llm = MockLLM([
        {"role": "assistant", "content": "A"},
        {"role": "assistant", "content": "B"},
    ])
    loop = AgentLoop(llm=llm, registry=ToolRegistry([]))
    emit = Collector()
    await loop.run_turn("first", emit)
    await loop.run_turn("second", emit)
    # second call includes: system, first user, first assistant, second user
    assert [m["role"] for m in llm.received[1]] == ["system", "user", "assistant", "user"]
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest tests/test_agent.py -q`
Expected: FAIL — ImportError.

- [ ] **Step 3: Implement**

`os/daemon/aios_daemon/agent.py`:
```python
MAX_HOPS = 5

SYSTEM_PROMPT = (
    "You are AIOS, an AI operating system. You control this computer through tools: "
    "app_launch (launch or list installed applications), file_ops (search/open/move/trash files), "
    "and sys_info (time, disk, memory, uptime). Use a tool whenever the user asks to act on "
    "apps, files, or the system. For general questions, answer directly and concisely. "
    "Never claim you performed an action unless a tool result confirms it."
)


class AgentLoop:
    def __init__(self, llm, registry, system_prompt=SYSTEM_PROMPT):
        self.llm = llm
        self.registry = registry
        self.history = [{"role": "system", "content": system_prompt}]

    async def run_turn(self, text, emit):
        self.history.append({"role": "user", "content": text})

        async def on_token(token):
            await emit({"event": "token", "text": token})

        for _ in range(MAX_HOPS):
            try:
                reply = await self.llm.chat(self.history, tools=self.registry.specs, on_token=on_token)
            except Exception as e:
                await emit({"event": "error", "text": f"Brain offline: {e}"})
                return

            self.history.append(reply)
            calls = reply.get("tool_calls")
            if not calls:
                await emit({"event": "done", "text": reply.get("content", "")})
                return

            for call in calls:
                name = call["function"]["name"]
                args = call["function"].get("arguments") or {}
                await emit({"event": "tool", "name": name})
                result = await self.registry.execute(name, args)
                self.history.append({"role": "tool", "content": result})

        await emit({"event": "done", "text": "I got stuck in a tool loop and stopped. Try rephrasing."})
```

- [ ] **Step 4: Run to verify pass**

Run: `.venv/bin/pytest tests/test_agent.py -q`
Expected: 5 passed. Then `.venv/bin/pytest -q` — full suite green (20 tests).

- [ ] **Step 5: Commit**

```bash
git add aios_daemon/agent.py tests/test_agent.py
git commit -m "feat: add AgentLoop with tool dispatch, hop limit, event emission"
```

---

### Task 6: FastAPI server (WS + static + health)

**Files:**
- Create: `os/daemon/aios_daemon/server.py`
- Create: `os/daemon/aios_daemon/__main__.py`
- Create: `os/daemon/tests/test_server.py`
- Create: `os/daemon/web/index.html` (placeholder for mount; real UI in Task 7)

- [ ] **Step 1: Write failing tests**

`os/daemon/tests/test_server.py`:
```python
from fastapi.testclient import TestClient

from aios_daemon.server import create_app


class MockLLM:
    def __init__(self, replies, healthy=True):
        self.replies = list(replies)
        self.healthy = healthy

    async def chat(self, messages, tools, on_token):
        reply = self.replies.pop(0)
        if reply.get("content"):
            await on_token(reply["content"])
        return reply

    async def health(self):
        return self.healthy


def test_health_ok():
    app = create_app(llm=MockLLM([], healthy=True))
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_health_brain_down():
    app = create_app(llm=MockLLM([], healthy=False))
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 503
    assert response.json() == {"ok": False}


def test_ws_chat_roundtrip():
    llm = MockLLM([{"role": "assistant", "content": "Paris"}])
    app = create_app(llm=llm)
    client = TestClient(app)
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"text": "capital of France?"})
        events = []
        while True:
            event = ws.receive_json()
            events.append(event)
            if event["event"] in ("done", "error"):
                break
    assert events[-1] == {"event": "done", "text": "Paris"}
    assert {"event": "token", "text": "Paris"} in events


def test_serves_index():
    app = create_app(llm=MockLLM([]))
    client = TestClient(app)
    response = client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
```

- [ ] **Step 2: Create placeholder web/index.html**

`os/daemon/web/index.html`:
```html
<!doctype html>
<html><head><title>AIOS</title></head><body>AIOS placeholder — real UI in Task 7</body></html>
```

- [ ] **Step 3: Run to verify failure**

Run: `.venv/bin/pytest tests/test_server.py -q`
Expected: FAIL — ImportError.

- [ ] **Step 4: Implement**

`os/daemon/aios_daemon/server.py`:
```python
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from .agent import AgentLoop
from .config import Config
from .ollama import OllamaClient
from .tools import AppLaunch, FileOps, SysInfo, ToolRegistry

WEB_DIR = Path(__file__).parent.parent / "web"


def create_app(llm=None, config=None):
    config = config or Config()
    llm = llm or OllamaClient(base_url=config.ollama_url, model=config.model)
    registry = ToolRegistry([AppLaunch(), FileOps(search_root=config.search_root), SysInfo()])

    app = FastAPI()

    @app.get("/health")
    async def health():
        ok = await llm.health()
        return JSONResponse({"ok": ok}, status_code=200 if ok else 503)

    @app.websocket("/ws")
    async def ws_chat(ws: WebSocket):
        await ws.accept()
        loop = AgentLoop(llm=llm, registry=registry)

        async def emit(event):
            await ws.send_json(event)

        try:
            while True:
                data = await ws.receive_json()
                text = (data.get("text") or "").strip()
                if text:
                    await loop.run_turn(text, emit)
        except WebSocketDisconnect:
            pass

    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
    return app
```

`os/daemon/aios_daemon/__main__.py`:
```python
import uvicorn

from .config import Config
from .server import create_app


def main():
    config = Config()
    uvicorn.run(create_app(config=config), host="127.0.0.1", port=config.port)


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run to verify pass**

Run: `.venv/bin/pytest -q`
Expected: 24 passed.

- [ ] **Step 6: Commit**

```bash
git add aios_daemon/server.py aios_daemon/__main__.py tests/test_server.py web/index.html
git commit -m "feat: add FastAPI server with WebSocket chat, health, static UI"
```

---

### Task 7: Web UI

**Files:**
- Modify: `os/daemon/web/index.html`
- Create: `os/daemon/web/app.js`
- Create: `os/daemon/web/style.css`

- [ ] **Step 1: Write index.html**

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AIOS</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div id="banner" class="hidden">
    Brain offline — check Ollama. <button id="retry">Retry</button>
  </div>
  <main id="feed"></main>
  <footer>
    <input id="input" type="text" placeholder="Ask AIOS anything…" autofocus autocomplete="off">
    <div id="spinner" class="hidden"></div>
  </footer>
  <script src="app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Write style.css**

```css
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { height: 100%; }
body {
  background: #000; color: #eee;
  font: 16px/1.5 -apple-system, "Cantarell", "Noto Sans", sans-serif;
  display: flex; flex-direction: column;
}
#banner {
  background: #e08600; color: #000; padding: 10px 16px; text-align: center;
}
#banner button { margin-left: 12px; }
.hidden { display: none !important; }
#feed { flex: 1; overflow-y: auto; padding: 24px; display: flex; flex-direction: column; gap: 12px; }
.msg { max-width: 70%; padding: 10px 14px; border-radius: 12px; white-space: pre-wrap; }
.user { background: #1a4fbf59; align-self: flex-end; }
.assistant { background: #ffffff14; align-self: flex-start; }
.error { background: #e0860022; color: #e08600; align-self: flex-start; }
.status { color: #888; font-family: monospace; font-size: 13px; }
footer { display: flex; align-items: center; gap: 12px; padding: 20px; }
#input {
  flex: 1; padding: 14px; font-size: 18px; color: #eee;
  background: #ffffff0f; border: none; border-radius: 14px; outline: none;
}
#spinner {
  width: 18px; height: 18px; border: 2px solid #555; border-top-color: #eee;
  border-radius: 50%; animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
```

- [ ] **Step 3: Write app.js**

```javascript
const feed = document.getElementById("feed");
const input = document.getElementById("input");
const banner = document.getElementById("banner");
const spinner = document.getElementById("spinner");
let ws = null;
let currentBubble = null;

function addMsg(cls, text) {
  const div = document.createElement("div");
  div.className = `msg ${cls}`;
  div.textContent = text;
  feed.appendChild(div);
  feed.scrollTop = feed.scrollHeight;
  return div;
}

function setBusy(busy) {
  input.disabled = busy;
  spinner.classList.toggle("hidden", !busy);
  if (!busy) input.focus();
}

function connect() {
  ws = new WebSocket(`ws://${location.host}/ws`);
  ws.onopen = () => banner.classList.add("hidden");
  ws.onclose = () => banner.classList.remove("hidden");
  ws.onmessage = (raw) => {
    const e = JSON.parse(raw.data);
    if (e.event === "token") {
      if (!currentBubble) currentBubble = addMsg("assistant", "");
      currentBubble.textContent += e.text;
      feed.scrollTop = feed.scrollHeight;
    } else if (e.event === "tool") {
      addMsg("status", `▸ ${e.name}`);
    } else if (e.event === "done") {
      if (currentBubble) currentBubble.textContent = e.text;
      else if (e.text) addMsg("assistant", e.text);
      currentBubble = null;
      setBusy(false);
    } else if (e.event === "error") {
      addMsg("error", e.text);
      banner.classList.remove("hidden");
      currentBubble = null;
      setBusy(false);
    }
  };
}

input.addEventListener("keydown", (ev) => {
  if (ev.key !== "Enter") return;
  const text = input.value.trim();
  if (!text || !ws || ws.readyState !== WebSocket.OPEN) return;
  input.value = "";
  addMsg("user", text);
  setBusy(true);
  ws.send(JSON.stringify({ text }));
});

document.getElementById("retry").addEventListener("click", () => {
  fetch("/health").then((r) => { if (r.ok) { banner.classList.add("hidden"); connect(); } });
});

connect();
```

- [ ] **Step 4: Manual test on macOS against live Ollama**

```bash
cd os/daemon
AIOS_MODEL=qwen2.5:14b .venv/bin/python -m aios_daemon &
sleep 2
open http://localhost:8800
```
Expected: dark chat UI. "what is 2+2" → streamed answer. "what time is it" → `▸ sys_info` status then answer. Stop Ollama → next message shows error + banner. Kill daemon after (`kill %1`).
(app_launch/file open won't work on macOS — Linux-only commands; that's expected, test those in the VM.)

- [ ] **Step 5: Run full suite, commit**

Run: `.venv/bin/pytest -q` — 24 passed (UI has no unit tests; `test_serves_index` covers mount).

```bash
git add web/
git commit -m "feat: add dark chat web UI with streaming and offline banner"
```

---

### Task 8: systemd units + provision.sh

**Files:**
- Create: `os/units/aios-daemon.service`
- Create: `os/units/aios-kiosk.service`
- Create: `os/provision.sh`

- [ ] **Step 1: Write aios-daemon.service**

`os/units/aios-daemon.service`:
```ini
[Unit]
Description=AIOS agent daemon
After=network-online.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=aios
WorkingDirectory=/opt/aios/daemon
Environment=AIOS_MODEL=qwen2.5:7b
ExecStart=/opt/aios/daemon/.venv/bin/python -m aios_daemon
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: Write aios-kiosk.service**

`os/units/aios-kiosk.service`:
```ini
[Unit]
Description=AIOS kiosk shell (cage + chromium)
After=aios-daemon.service systemd-user-sessions.service
Wants=aios-daemon.service
Conflicts=getty@tty1.service

[Service]
Type=simple
User=aios
PAMName=login
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=journal
UtmpIdentifier=tty1
ExecStartPre=/usr/bin/bash -c 'until curl -sf http://localhost:8800/ >/dev/null; do sleep 1; done'
ExecStart=/usr/bin/cage -- /usr/bin/chromium-browser --kiosk --noerrdialogs --disable-session-crashed-bubble --app=http://localhost:8800
Restart=always
RestartSec=2

[Install]
WantedBy=graphical.target
```

- [ ] **Step 3: Write provision.sh**

`os/provision.sh`:
```bash
#!/usr/bin/env bash
# Converts stock Fedora Minimal (aarch64) into AIOS. Idempotent. Run as root
# from the os/ directory: sudo bash provision.sh
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Installing packages"
dnf install -y cage chromium python3 python3-pip curl git glib2 xdg-utils

echo "==> Installing Ollama"
if ! command -v ollama >/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
systemctl enable --now ollama

echo "==> Pulling model (skips if present)"
ollama pull "${AIOS_MODEL:-qwen2.5:7b}"

echo "==> Creating aios user"
id aios &>/dev/null || useradd -m -G video,input,render aios

echo "==> Installing daemon to /opt/aios"
mkdir -p /opt/aios
rsync -a --delete daemon/ /opt/aios/daemon/ --exclude .venv --exclude __pycache__
python3 -m venv /opt/aios/daemon/.venv
/opt/aios/daemon/.venv/bin/pip install -q /opt/aios/daemon
chown -R aios:aios /opt/aios

echo "==> Installing systemd units"
cp units/aios-daemon.service units/aios-kiosk.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable aios-daemon aios-kiosk
systemctl set-default graphical.target

echo "==> Starting services"
systemctl restart aios-daemon
systemctl restart aios-kiosk || true   # fails harmlessly when run over SSH without tty1

echo "==> AIOS provisioned. Reboot to enter the kiosk shell."
```

- [ ] **Step 4: Sanity-check script syntax**

Run: `bash -n os/provision.sh`
Expected: no output (syntax OK).

- [ ] **Step 5: Commit**

```bash
git add os/units os/provision.sh
git commit -m "feat: add systemd units and Fedora provisioner for AIOS"
```

---

### Task 9: Live integration test + docs

**Files:**
- Create: `os/daemon/tests/test_live.py`
- Create: `os/README.md`
- Create: `README.md` (new repo root)

- [ ] **Step 1: Write live test**

`os/daemon/tests/test_live.py`:
```python
"""Live tests against a running Ollama. Run: pytest -m live"""
import os

import pytest

from aios_daemon.agent import SYSTEM_PROMPT
from aios_daemon.ollama import OllamaClient
from aios_daemon.tools import AppLaunch, FileOps, SysInfo, ToolRegistry

MODEL = os.environ.get("AIOS_MODEL", "qwen2.5:7b")

pytestmark = pytest.mark.live


async def test_model_calls_app_launch():
    client = OllamaClient(base_url="http://localhost:11434", model=MODEL)
    if not await client.health():
        pytest.skip("Ollama not running or model not pulled")

    registry = ToolRegistry([AppLaunch(), FileOps(search_root="/tmp"), SysInfo()])

    async def on_token(t):
        pass

    reply = await client.chat(
        [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": "Open the Firefox browser"},
        ],
        tools=registry.specs,
        on_token=on_token,
    )
    calls = reply.get("tool_calls") or []
    assert calls, f"expected a tool call, got content: {reply['content']!r}"
    assert calls[0]["function"]["name"] == "app_launch"
```

- [ ] **Step 2: Run it live (on macOS, model qwen2.5:14b is pulled)**

Run: `cd os/daemon && AIOS_MODEL=qwen2.5:14b .venv/bin/pytest -m live -q`
Expected: 1 passed (10-60s). Also verify default suite still excludes it cleanly: `.venv/bin/pytest -q -m "not live"` → 24 passed.

- [ ] **Step 3: Write os/README.md**

```markdown
# AIOS Linux

Bootable AI-first OS: Fedora + provisioner that boots straight into a
full-screen AI chat shell backed by a local LLM.

## Layout
- `daemon/` — Python agent daemon (FastAPI, WebSocket, tools, Ollama client)
- `units/` — systemd units (daemon + cage/Chromium kiosk)
- `provision.sh` — turns stock Fedora Minimal (aarch64) into AIOS

## Develop on macOS
```bash
cd daemon
python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/pytest -q -m "not live"      # unit tests
AIOS_MODEL=qwen2.5:14b .venv/bin/python -m aios_daemon   # then open :8800
```

## VM bring-up (UTM on Apple Silicon)
1. Download Fedora Minimal aarch64 (Fedora 42) ISO/raw image.
2. UTM: new VM, Virtualize, Linux, 8GB RAM, 4 cores, 40GB disk. Install.
3. In the VM: `sudo dnf install -y git && git clone <this repo> && cd AI_OS/os`
4. `sudo bash provision.sh` (pulls qwen2.5:7b, ~4.7GB)
5. `sudo reboot` → boots into the AIOS kiosk.

## Bare metal (M1/M2)
Install Fedora Asahi Remix (asahilinux.org), then run the same provisioner.
Set `AIOS_MODEL=qwen2.5:14b` before running for the bigger model.
```

- [ ] **Step 4: Write repo-root README.md**

```markdown
# AIOS

An AI-first operating system. Two implementations:

- **`os/`** — bootable Linux OS (Fedora + kiosk AI shell, local LLM). The product.
- **`macos/`** — native macOS full-screen AI shell (Swift). Reference implementation.

See `os/README.md` to build/run the OS, and `docs/superpowers/specs/` for designs.
```

- [ ] **Step 5: Full suite + commit**

Run: `cd os/daemon && .venv/bin/pytest -q -m "not live"`
Expected: 24 passed.

```bash
git add os/daemon/tests/test_live.py os/README.md README.md
git commit -m "test: add live Ollama integration test; add OS and root READMEs"
```

---

## Manual Acceptance Checklist (VM)

- [ ] Fedora VM provisioned via `provision.sh`, reboots into full-screen kiosk
- [ ] "what is the capital of Japan" → direct streamed answer
- [ ] "what time is it" → `▸ sys_info` → answer
- [ ] "open firefox" → `▸ app_launch` → Firefox opens over kiosk
- [ ] "find files named bashrc" → `▸ file_ops` → paths listed
- [ ] Stop ollama (`systemctl stop ollama`) → error banner; start + Retry → recovers
- [ ] Reboot → kiosk returns automatically
