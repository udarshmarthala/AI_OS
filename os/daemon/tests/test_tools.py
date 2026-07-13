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
