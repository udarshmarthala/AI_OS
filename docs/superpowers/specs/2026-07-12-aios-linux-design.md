# AIOS Linux — Bootable AI-First OS (v1 Design)

Date: 2026-07-12
Status: Approved by user

## Vision

A bootable Linux OS whose entire user interface is an AI chat shell. Boots
straight into a full-screen AI (no desktop, no login screen ceremony); the AI
launches apps, manages files, and answers questions via a local LLM.

Developed and tested in a VM on the user's Mac (M1/M2, 16GB). The same
provisioner later targets bare-metal Apple Silicon via Asahi Linux (Fedora
Asahi Remix uses the same Fedora base).

## Strategy: distro-as-provisioner

v1 is NOT a custom ISO. It is a stock Fedora Minimal (aarch64) install plus an
idempotent provisioning script that converts it into AIOS. A real image build
(mkosi/osbuild) is deferred to v2. Bare-metal Asahi install is sub-project 2.

## Scope (v1)

**In:**
- `provision.sh` — stock Fedora Minimal → AIOS (packages, services, autologin, kiosk)
- Python daemon (FastAPI): web UI serving, WebSocket chat, agent loop,
  streaming Ollama client, tool registry
- Tools: `app_launch` (launch installed GUI apps), `file_ops`
  (search/open/move/trash), `sys_info` (time, disk, memory, battery)
- Web UI: dark full-screen chat, live token streaming, tool status lines
- Ollama with `qwen2.5:7b` (VM) / `qwen2.5:14b` (bare metal, config swap)
- Wayland kiosk: cage + Chromium `--kiosk`
- pytest suite for all daemon logic

**Out (later):**
- Custom ISO/image build
- Bare-metal Asahi install (sub-project 2)
- Voice input (VM mic passthrough pain; revisit on bare metal)
- Multi-user, persistence of chat history across reboots
- Screen click/type computer-use

## Repo layout

```
macos/          — existing Swift macOS shell app (moved, unchanged)
os/
  provision.sh          — idempotent provisioner (run as root on Fedora)
  units/aios-daemon.service
  units/aios-kiosk.service
  daemon/
    pyproject.toml
    aios_daemon/
      server.py         — FastAPI app: static files, /ws, /health
      agent.py          — AgentLoop
      ollama.py         — OllamaClient (async, streaming, tools)
      tools.py          — ToolRegistry + app_launch, file_ops, sys_info
      config.py         — model name, ports, paths (env-overridable)
    web/
      index.html
      app.js
      style.css
    tests/
      test_tools.py
      test_agent.py
      test_ollama.py
docs/           — specs and plans
```

## Architecture

```
systemd
 ├─ ollama.service            (:11434, qwen2.5:7b)
 ├─ aios-daemon.service       (:8800, python -m aios_daemon)
 └─ aios-kiosk.service        (cage -> chromium --kiosk http://localhost:8800)

Browser (kiosk) ⇄ WebSocket /ws ⇄ AgentLoop ⇄ OllamaClient ⇄ Ollama
                                      │
                                  ToolRegistry
                                  app_launch / file_ops / sys_info
```

## WebSocket protocol

Client → server: `{"text": "user message"}`

Server → client events (JSON, one per frame):
- `{"event":"token","text":"..."}` — streamed content token
- `{"event":"tool","name":"file_ops"}` — tool call started
- `{"event":"done","text":"full final reply"}` — turn complete
- `{"event":"error","text":"Brain offline: ..."}` — failure surfaced

## Agent loop

History starts with system prompt (AI OS persona, tool guidance, "never claim
an action without a tool result"). Per user turn: append user message → call
Ollama with tool schemas (streaming) → if tool_calls: execute each via
registry, append results as `tool` role messages, loop (max 5 hops) → emit
done. Ollama errors → `error` event, turn ends. Tool errors → returned as
strings into history (model self-corrects).

## Tools

- `app_launch(name)` — match against installed .desktop entries
  (`/usr/share/applications`), launch via `gio launch` / `gtk-launch`.
  Errors if no match.
- `file_ops(action, query|path|destination)` — search (`find` in $HOME, capped
  20 results), open (`xdg-open`), move, trash (`gio trash`). Never `rm`.
- `sys_info()` — time, disk free, memory, uptime; single JSON-ish string.

## Error handling

- Ollama unreachable → `error` WS event; UI shows orange banner + Retry
  (re-opens WS / re-checks `/health`)
- `/health` endpoint: daemon up + Ollama reachable + model present
- Malformed/unknown tool calls → error string fed back to model, one loop hop
- Hop limit 5 → "stuck in a tool loop" message
- Kiosk service `Restart=always`; daemon `Restart=on-failure`

## Testing

- pytest, no network: ToolRegistry dispatch, each tool against tmp dirs/fakes,
  AgentLoop with scripted mock LLM (plain answer, tool loop, hop limit,
  LLM error), OllamaClient against local aiohttp mock server
- Live integration test (marked, skipped when Ollama down): "Open the text
  editor" → expects `app_launch` tool call
- Manual: boot VM → kiosk appears → golden path prompts

## VM development environment

- UTM (or `vfkit`) on macOS, aarch64 Fedora Minimal 42 cloud/server image,
  8GB RAM, 4 cores, 40GB disk
- Iterate: `rsync` os/ into VM + rerun provision.sh, or edit in place
- Daemon can also run on macOS directly for fast unit-test cycles (all logic
  OS-agnostic except tools; tools guarded/testable via fakes)

## Decisions log

- Fedora Minimal base: matches Fedora Asahi Remix → provisioner ports to bare
  metal with minimal change
- Python daemon over Swift port: faster iteration, better Linux ecosystem;
  Swift version remains in macos/ as reference implementation
- cage over full compositor: single-app kiosk is exactly the product shape
- qwen2.5:7b in VM: 14b does not fit in an 8GB-RAM VM alongside Chromium
- Chat history RAM-only: YAGNI for v1
