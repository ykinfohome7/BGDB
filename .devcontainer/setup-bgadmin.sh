#!/usr/bin/env bash
set -euo pipefail

# Non-interactive setup. Keep password prompts out of Codespaces postStartCommand.
if ! id bgadmin >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash bgadmin
fi
usermod -aG sudo,adm,root,users bgadmin

export DEBIAN_FRONTEND=noninteractive
if ! command -v sshd >/dev/null 2>&1 && [ ! -x /usr/sbin/sshd ]; then
  apt-get update
  apt-get install -y --no-install-recommends openssh-server
fi
mkdir -p /etc/ssh/sshd_config.d /run/sshd
cat > /etc/ssh/sshd_config.d/00-bgdb-password.conf <<'SSHD_CONF'
PasswordAuthentication yes
PermitEmptyPasswords no
SSHD_CONF
/usr/sbin/sshd -t
service ssh reload >/dev/null 2>&1 || service ssh start >/dev/null 2>&1 || /usr/sbin/sshd

# Tailscale Codespaces feature normally installs the client and launches tailscaled.
# If the feature is absent, use the official Debian 13 (Trixie) package repository.
if ! command -v tailscale >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl
  mkdir -p -m 0755 /usr/share/keyrings
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
    -o /etc/apt/sources.list.d/tailscale.list
  apt-get update
  apt-get install -y --no-install-recommends tailscale
fi

if ! pgrep -x tailscaled >/dev/null 2>&1; then
  if ! service tailscaled start >/dev/null 2>&1; then
    mkdir -p /var/lib/tailscale
    nohup "$(command -v tailscaled)" --state=/var/lib/tailscale/tailscaled.state \
      >/tmp/bgdb-tailscaled.log 2>&1 </dev/null &
  fi
fi

# First interactive terminal: password, SSH check, Tailscale login.
while IFS=: read -r account _ uid _ _ home shell; do
  if [ "$uid" -ge 1000 ] 2>/dev/null && [ "$uid" -lt 60000 ] 2>/dev/null && [ -f "$home/.bashrc" ]; then
    if ! grep -Fq '# BGDB first-run setup hook' "$home/.bashrc"; then
      cat >> "$home/.bashrc" <<'BASHRC_HOOK'

# BGDB first-run setup hook
if [ -t 0 ] && [ -t 1 ] && [ -f /workspaces/BGDB/.devcontainer/finish-bgdb-setup.sh ] && [ "${BGDB_SETUP_RUNNING:-0}" != 1 ]; then
  export BGDB_SETUP_RUNNING=1
  bash /workspaces/BGDB/.devcontainer/finish-bgdb-setup.sh
  unset BGDB_SETUP_RUNNING
fi
BASHRC_HOOK
    fi
  fi
done < /etc/passwd

printf '\nBGDB bootstrap complete. Interactive terminal will prompt for password, then Tailscale login.\n'
id bgadmin
