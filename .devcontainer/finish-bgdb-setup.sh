#!/usr/bin/env bash
set -u
[ -t 0 ] && [ -t 1 ] || exit 0

printf '\n=== BGDB SSH + TAILSCALE FIRST-RUN SETUP ===\n'
if ! sudo -n true >/dev/null 2>&1; then
  echo 'Administrative sudo is required. From your Codespaces user, run: sudo bash .devcontainer/finish-bgdb-setup.sh'
  exit 0
fi

password_state="$(sudo -n passwd -S bgadmin 2>/dev/null | awk '{print $2}' || true)"
if [ "$password_state" != P ]; then
  echo 'STEP 1/3: Set your bgadmin login password below. It is NOT saved in GitHub.'
  if ! sudo passwd bgadmin; then
    echo 'Password not set. Reopen a terminal to retry.'
    exit 0
  fi
else
  echo 'STEP 1/3: bgadmin password is already configured.'
fi

printf '\nSTEP 2/3: Checking SSH server...\n'
if sudo -n /usr/sbin/sshd -t && (sudo -n service ssh reload || sudo -n service ssh start); then
  echo 'SSH configured for password login. Use private Tailscale access.'
else
  echo 'SSH could not be started. Check the startup log.'
fi

printf '\nSTEP 3/3: Connecting Tailscale...\n'
if ! command -v tailscale >/dev/null 2>&1; then
  echo 'Tailscale binary missing. Review Codespaces startup output.'
elif ! tailscale ip -4 2>/dev/null | grep -Eq '^100\.'; then
  echo 'Open the login URL printed below and authorize this Codespace in your tailnet.'
  sudo -n tailscale up --accept-routes || echo 'Tailscale needs another login attempt.'
else
  echo 'Tailscale is already connected.'
fi
bash /workspaces/BGDB/.devcontainer/show-connection.sh
