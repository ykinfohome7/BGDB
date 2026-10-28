#!/usr/bin/env bash
# Инсталира само липсващите пакети за AI-EMDS/Paperclip в Debian 13.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
if [[ "$EUID" -ne 0 ]]; then
  echo "[AI-EMDS] Run OS package check as root (sudo)." >&2
  exit 1
fi
command -v apt-get >/dev/null || { echo "[AI-EMDS] APT not found." >&2; exit 1; }

# Rust е необходим за native Runner; компилаторите са за Node зависимости.
packages=(
  ca-certificates curl git openssh-client
  python3 python3-venv python3-pip python3-pytest python3-yaml
  build-essential pkg-config libssl-dev
  gh shellcheck jq unzip rsync
  rustc cargo
)
missing=()
for pkg in "${packages[@]}"; do
  if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" != "install ok installed" ]]; then
    missing+=("$pkg")
  fi
done
if (( ${#missing[@]} == 0 )); then
  echo "[AI-EMDS] All Debian 13 packages already installed."
  exit 0
fi
printf '[AI-EMDS] Installing missing OS packages: %s\n' "${missing[*]}"
apt-get update
apt-get install -y --no-install-recommends "${missing[@]}"
echo "[AI-EMDS] Debian dependencies ready. No dist-upgrade or server changes performed."
