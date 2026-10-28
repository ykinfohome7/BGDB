#!/usr/bin/env bash
# Първа фаза: права на /tmp, системен Python 3.13, Debian SSH/base packages.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
ROOT="$(cd "$(dirname "$0")" && pwd)"
if (( EUID != 0 )); then
  echo "[BGDB] Debian/Python bootstrap requires sudo." >&2
  exit 1
fi
run_upgrade=1
if (( $# > 1 )); then
  echo "[BGDB] Usage: $0 [--no-upgrade]" >&2
  exit 2
elif (( $# == 1 )); then
  if [[ "$1" == "--no-upgrade" ]]; then
    run_upgrade=0
  else
    echo "[BGDB] Unknown option." >&2
    exit 2
  fi
fi

# Безопасността на /tmp е предпоставка за pip, npm, cargo, mktemp и PostgreSQL.
bash "$ROOT/fix-tmp-permissions.sh"
updated=0
install_missing() {
  local stage="$1"
  shift
  local missing=() pkg
  for pkg in "$@"; do
    if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" != "install ok installed" ]]; then
      missing+=("$pkg")
    fi
  done
  if (( ${#missing[@]} == 0 )); then
    echo "[BGDB] $stage: already installed."
    return 0
  fi
  if (( updated == 0 )); then
    apt-get update
    updated=1
  fi
  echo "[BGDB] Installing $stage: ${missing[*]}"
  apt-get install -y --no-install-recommends "${missing[@]}"
}

# Python се настройва преди всички останали AI и Node инструменти.
install_missing "Python 3.13 and tooling" \
  python3 python3.13 libpython3.13-stdlib python3.13-venv \
  python3-venv python3-pip-whl python3-setuptools-whl \
  python3-pip python3-pytest python3-yaml

if ! /usr/bin/python3 -I -c 'import secrets, venv, ssl, ensurepip, yaml, pytest' >/dev/null 2>&1; then
  echo "[BGDB] Python verification failed; repairing Python components."
  if (( updated == 0 )); then apt-get update; updated=1; fi
  apt-get install -y --no-install-recommends --reinstall \
    python3.13 libpython3.13-stdlib python3.13-venv \
    python3-pip-whl python3-setuptools-whl python3-yaml python3-pytest
fi
/usr/bin/python3 -I -c 'import secrets,venv,ssl,ensurepip,yaml,pytest; print("[BGDB] Python 3.13 stdlib, TLS, venv, pytest and YAML: OK")'

# Базата на Debian и SSH се проверява след Python и преди AI пакетите.
install_missing "Debian baseline and SSH" \
  ca-certificates curl git openssh-client openssh-server \
  sudo procps iproute2

# Актуализацията на системата е при postCreate; postStart не прави dist-upgrade.
if (( run_upgrade == 1 )); then
  echo "[BGDB] Running Debian safe full-upgrade (no package removals)."
  if (( updated == 0 )); then apt-get update; fi
  if ! apt-get -y --no-remove dist-upgrade; then
    echo "[BGDB] WARNING: Full-upgrade needs manual review; SSH files preserved." >&2
  fi
fi
echo "[BGDB] Debian/Python baseline ready."
