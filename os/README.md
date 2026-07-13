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
