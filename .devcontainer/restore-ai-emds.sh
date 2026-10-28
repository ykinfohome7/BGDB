#!/usr/bin/env bash
# Трета фаза: след Debian/Python и останалите пакети възстанови Paperclip.
set -Eeuo pipefail
ROOT=/workspaces/BGDB/.devcontainer
[[ "$(id -un)" == vscode ]] || {
  echo "[AI-EMDS] Expected vscode postStart user." >&2
  exit 1
}
# AI-EMDS пакетите са втората фаза; при временен APT проблем не губим Paperclip.
if sudo -n true >/dev/null 2>&1; then
  if ! sudo -n bash "$ROOT/install-ai-emds-deps.sh"; then
    echo "[AI-EMDS] WARNING: Additional packages incomplete; checking Paperclip prerequisites." >&2
  fi
else
  echo "[AI-EMDS] WARNING: sudo unavailable; cannot repair missing packages." >&2
fi

# BGDB Paperclip работи само като bgadmin, без root или публичен порт.
sudo -n -u bgadmin -H bash "$ROOT/start-ai-emds-paperclip.sh"
