#!/usr/bin/env bash
# BGDB Codespaces / Debian 13: explicit baseline packages for SSH, BGSSH and Python MCP.
# Runs after container creation and verifies/repairs the installation on every start.
# Idempotent: apt-get is used only for absent packages or a broken Python stdlib.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

if (( EUID != 0 )); then
  echo "[BGDB] Run Debian dependency bootstrap via sudo." >&2
  exit 1
fi

packages=(
  ca-certificates curl git openssh-client openssh-server
  sudo procps iproute2
  python3 python3.13 libpython3.13-stdlib python3.13-venv
  python3-venv python3-pip-whl python3-setuptools-whl
)
missing=()
for pkg in "${packages[@]}"; do
  if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" != "install ok installed" ]]; then
    missing+=("$pkg")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf '[BGDB] Installing missing Debian 13 packages: %s\n' "${missing[*]}"
  apt-get update
  apt-get install -y --no-install-recommends "${missing[@]}"
else
  echo "[BGDB] Debian 13 base dependencies are already installed."
fi

# A package may be recorded as installed even if its files are incomplete.
# Isolated Python avoids a bad PYTHONPATH from the interactive login shell.
if ! /usr/bin/python3 -I -c 'import secrets, venv, ssl, ensurepip' >/dev/null 2>&1; then
  echo "[BGDB] Python 3.13 stdlib/venv check failed; repairing the affected packages."
  apt-get update
  apt-get install -y --no-install-recommends --reinstall \
    python3.13 libpython3.13-stdlib python3.13-venv \
    python3-pip-whl python3-setuptools-whl
fi

/usr/bin/python3 -I -c 'import secrets, venv, ssl, ensurepip; print("[BGDB] Python 3.13 stdlib and venv: OK")'
/usr/sbin/sshd -t 2>/dev/null || {
  echo "[BGDB] SSH configuration test deferred to setup-bgadmin.sh." >&2
}
echo "[BGDB] Debian dependencies: OK."
