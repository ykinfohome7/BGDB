#!/usr/bin/env bash
# Възстановява стандартните права на /tmp и лично TMP пространство за bgadmin.
set -Eeuo pipefail

if (( EUID != 0 )); then
  echo "[BGDB] /tmp permission repair requires root (sudo)." >&2
  exit 1
fi
if [[ ! -d /tmp || -L /tmp ]]; then
  echo "[BGDB] /tmp is missing or is a symlink; refusing unsafe changes." >&2
  exit 1
fi

# /tmp остава root:root; sticky bit не позволява изтриване на чужди файлове.
chown root:root /tmp
chmod 1777 /tmp
if [[ "$(stat -c '%a:%U:%G' /tmp)" != "1777:root:root" ]]; then
  echo "[BGDB] /tmp permissions could not be verified." >&2
  exit 1
fi

# Потребителят има отделна частна временна директория, не цялата /tmp.
if id bgadmin >/dev/null 2>&1; then
  if [[ -L /tmp/bgadmin ]]; then
    echo "[BGDB] /tmp/bgadmin is a symlink; refusing to replace it." >&2
    exit 1
  fi
  install -d -o bgadmin -g bgadmin -m 0700 /tmp/bgadmin
  [[ "$(stat -c '%a:%U:%G' /tmp/bgadmin)" == "700:bgadmin:bgadmin" ]] || {
    echo "[BGDB] Private bgadmin temporary directory is not safe." >&2
    exit 1
  }
  if command -v runuser >/dev/null 2>&1; then
    # Проверява действителен запис от bgadmin.
    testfile="$(runuser -u bgadmin -- mktemp /tmp/bgadmin/write-check.XXXXXXXX)"
    runuser -u bgadmin -- rm -f -- "$testfile"
  fi
fi
echo "[BGDB] /tmp=root:root 1777; /tmp/bgadmin=bgadmin:bgadmin 0700; permission check OK."
