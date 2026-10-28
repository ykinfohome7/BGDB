#!/usr/bin/env bash
# Втора фаза: допълнителни инструменти СЛЕД системния Python/Debian bootstrap.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
if (( EUID != 0 )); then
  echo "[AI-EMDS] Additional OS packages require root (sudo)." >&2
  exit 1
fi
# Не започвай AI инсталации преди успешна Python проверка.
if ! /usr/bin/python3 -I -c 'import secrets,venv,ssl,ensurepip,yaml,pytest' >/dev/null 2>&1; then
  echo "[AI-EMDS] Python prerequisites missing; run install-debian-deps.sh first." >&2
  exit 1
fi
packages=(build-essential pkg-config libssl-dev gh shellcheck jq unzip rsync rustc cargo)
missing=()
for pkg in "${packages[@]}"; do
  if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" != "install ok installed" ]]; then
    missing+=("$pkg")
  fi
done
if (( ${#missing[@]} == 0 )); then
  echo "[AI-EMDS] Additional Debian packages already installed."
  exit 0
fi
echo "[AI-EMDS] Installing additional packages: ${missing[*]}"
apt-get update
apt-get install -y --no-install-recommends "${missing[@]}"
echo "[AI-EMDS] Additional tools ready; no system upgrade performed."
