#!/usr/bin/env bash
set -euo pipefail
if ! id bgadmin >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash bgadmin
fi
usermod -aG sudo,adm,root,users bgadmin
printf 'bgadmin groups: '
id -nG bgadmin
