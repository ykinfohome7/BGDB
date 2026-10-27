#!/usr/bin/env bash
set -euo pipefail

# Idempotent: create bgadmin only if missing, retain any password already set.
if ! id bgadmin >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash bgadmin
fi
usermod -aG sudo,adm,root,users bgadmin

# Show Codespace connection information whenever an interactive bash terminal opens.
for account in bgadmin "${SUDO_USER:-vscode}"; do
  home_dir="$(getent passwd "$account" | cut -d: -f6 || true)"
  if [ -n "$home_dir" ] && [ -f "$home_dir/.bashrc" ]; then
    if ! grep -Fq '# BGDB Codespace connection information' "$home_dir/.bashrc"; then
      cat >> "$home_dir/.bashrc" <<'HOOK'

# BGDB Codespace connection information
if [ -t 1 ] && [ -f /workspaces/BGDB/.devcontainer/show-connection.sh ]; then
  bash /workspaces/BGDB/.devcontainer/show-connection.sh
fi
HOOK
    fi
  fi
done

printf 'bgadmin groups: '
id -nG bgadmin
bash /workspaces/BGDB/.devcontainer/show-connection.sh
