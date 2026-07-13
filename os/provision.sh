#!/usr/bin/env bash
# Converts stock Fedora Minimal (aarch64) into AIOS. Idempotent. Run as root
# from the os/ directory: sudo bash provision.sh
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Installing packages"
dnf install -y cage chromium python3 python3-pip curl git glib2 xdg-utils rsync

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
rsync -a --delete --exclude .venv --exclude __pycache__ --exclude '*.egg-info' daemon/ /opt/aios/daemon/
python3 -m venv /opt/aios/daemon/.venv
/opt/aios/daemon/.venv/bin/pip install -q /opt/aios/daemon
chown -R aios:aios /opt/aios

echo "==> Normalizing chromium binary"
[ -x /usr/bin/chromium-browser ] || ln -sf /usr/bin/chromium /usr/bin/chromium-browser

echo "==> Installing systemd units"
cp units/aios-daemon.service units/aios-kiosk.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable aios-daemon aios-kiosk
systemctl set-default graphical.target

echo "==> Starting services"
systemctl restart aios-daemon
systemctl restart aios-kiosk || true   # fails harmlessly when run over SSH without tty1

echo "==> AIOS provisioned. Reboot to enter the kiosk shell."
