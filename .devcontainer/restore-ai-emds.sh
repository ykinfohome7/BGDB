#!/usr/bin/env bash
# Възстановява AI-EMDS след BGSSH; не променя SSH, DNS, Tailscale или публични портове.
set -Eeuo pipefail
ROOT=/workspaces/BGDB/.devcontainer
[[ "$(id -un)" == vscode ]] || { echo "[AI-EMDS] Expected vscode postStart user." >&2; exit 1; }
if ! sudo -n true >/dev/null 2>&1; then
  echo "[AI-EMDS] Noninteractive sudo unavailable; skip OS install and service start." >&2
  exit 1
fi
# Операцията е отделна от основния SSH boot, за да не блокира KSSH.
sudo -n bash "$ROOT/install-ai-emds-deps.sh"
sudo -n -u bgadmin -H bash "$ROOT/start-ai-emds-paperclip.sh"
