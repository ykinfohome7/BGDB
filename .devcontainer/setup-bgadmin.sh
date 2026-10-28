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

# Preserve the Codespace SSH HOST identity across stop/start and rebuilds.
# Named Docker volume configured in devcontainer.json persists for this Codespace.
# TLS certificate for bgssh.abrdns.com is unrelated to SSH host keys.
SSH_KEY_STORE=/var/lib/bgdb-ssh-hostkeys
mkdir -p "$SSH_KEY_STORE"
chmod 700 "$SSH_KEY_STORE"
if compgen -G "$SSH_KEY_STORE/ssh_host_*_key" > /dev/null; then
  for key in "$SSH_KEY_STORE"/ssh_host_*_key; do
    [ -f "$key" ] || continue
    install -m 0600 "$key" "/etc/ssh/$(basename "$key")"
    if [ -f "$key.pub" ]; then
      install -m 0644 "$key.pub" "/etc/ssh/$(basename "$key").pub"
    fi
  done
else
  ssh-keygen -A >/dev/null
  for key in /etc/ssh/ssh_host_*_key; do
    [ -f "$key" ] || continue
    install -m 0600 "$key" "$SSH_KEY_STORE/$(basename "$key")"
    if [ -f "$key.pub" ]; then
      install -m 0644 "$key.pub" "$SSH_KEY_STORE/$(basename "$key").pub"
    fi
  done
fi

# BGSSH workflow targets the BGDB Codespace on Tailscale port 2222.
# Preserve pre-existing password policy; do not change passwords on boot.
cat > /etc/ssh/sshd_config.d/00-bgdb-password.conf <<'SSHD_CONF'
Port 2222
PasswordAuthentication yes
PermitEmptyPasswords no
PermitRootLogin yes
SSHD_CONF
/usr/sbin/sshd -t
if ! /usr/sbin/sshd -T | grep -qx 'port 2222'; then
  echo 'ERROR: BGDB sshd is NOT configured for port 2222' >&2
  exit 1
fi
service ssh reload >/dev/null 2>&1 || service ssh start >/dev/null 2>&1 || /usr/sbin/sshd
if command -v ss >/dev/null 2>&1; then
  ss -ltn | awk '$4 ~ /:2222$/ { found=1 } END {exit !found}' ||
    { echo 'ERROR: BGDB sshd does not listen on 2222' >&2; exit 1; }
fi
echo 'BGDB SSH: port 2222 is configured and listening.'
# Public key fingerprint can be compared to the GitHub SSH_CONNECTOR_KNOWN_HOSTS secret.
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null |
  awk '{print "BGDB SSH ED25519 fingerprint: " $2}' || true

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
