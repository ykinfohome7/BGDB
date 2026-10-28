#!/usr/bin/env bash
# BGDB Codespace auto-restore on every start (and after Rebuild Container).
# No plaintext passwords, API tokens, TLS private keys or DDNS URLs are logged.
set -Eeuo pipefail

BASE=/workspaces/BGDB/.devcontainer
say() { printf '[BGDB restore] %s\n' "$*"; }
warn() { printf '[BGDB restore] WARNING: %s\n' "$*" >&2; }

if [ ! -f "$BASE/setup-bgadmin.sh" ]; then
  echo 'BGDB workspace not found at /workspaces/BGDB. Nothing changed.' >&2
  exit 1
fi

say '1/4 Restoring SSH service, original host identity, and port 2222...'
sudo -n bash "$BASE/setup-bgadmin.sh"

# Named volumes are initially root-owned on some Codespaces; let vscode write its own data.
sudo -n mkdir -p "$HOME/.codex" "$HOME/.local/share/bgdb-ai-tools"
sudo -n chown "$(id -u):$(id -g)" "$HOME/.codex" "$HOME/.local/share/bgdb-ai-tools"
say '2/4 Restoring Claude Code and Codex binaries (authentication retained in private volumes)...'
if ! bash "$BASE/setup-ai-tools.sh"; then
  warn 'AI CLI restore incomplete. Check Node.js and run: bash .devcontainer/setup-ai-tools.sh'
fi

say '3/4 Checking Tailscale...'
if command -v tailscale >/dev/null 2>&1; then
  if ip="$(tailscale ip -4 2>/dev/null)" && [[ "$ip" == 100.* ]]; then
    say "Tailscale connected (private IPv4: $ip)"
  else
    warn 'Tailscale requires authorization: open a new interactive terminal, then follow first-run setup.'
  fi
else
  warn 'Tailscale missing; Codespaces feature or package installation needs repair.'
fi

say '4/4 Checking BGDB target for BGSSH GitHub connector...'
if sudo -n /usr/sbin/sshd -T | grep -qx 'port 2222'; then
  say 'SSH port 2222 configured.'
else
  warn 'SSH port 2222 not configured: BGSSH cannot connect.'
  exit 1
fi
if [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub |
    awk '{ print "[BGDB restore] SSH ED25519 public fingerprint: " $2 }'
fi
say 'No DNS A record or HTTPS certificate was changed.'
say "bgssh.abrdns.com Let's Encrypt certificate belongs on HTTPS ingress, not SSH port 2222."
say 'If SSH host fingerprint or Tailscale IPv4 changed after a new Codespace, update and verify the BGSSH connector profile.'
say 'Codespace boot restoration finished.'
