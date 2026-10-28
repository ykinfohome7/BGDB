#!/usr/bin/env bash
# BGDB Codespace: idempotent root bootstrap, private SSH port 2222 and stable host keys.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo -n bash .devcontainer/setup-bgadmin.sh" >&2
  exit 1
fi

if ! id bgadmin >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash bgadmin
fi
usermod -aG sudo,adm,root,users bgadmin

# Recheck packages on EVERY Codespace start. Missing Debian 13 packages are
# installed idempotently; an incomplete Python stdlib is repaired as needed.
# The same script runs once in postCreateCommand on initial build.
bash /workspaces/BGDB/.devcontainer/install-debian-deps.sh

mkdir -p /etc/ssh/sshd_config.d /run/sshd

# Do not change existing login credentials, root password or authorization.
# Keep the original BGDB password authentication policy for compatibility;
# SSH is intended for private Tailscale access, NEVER public port forwarding.
cat > /etc/ssh/sshd_config.d/00-bgdb-password.conf <<'SSHD_CONF'
Port 2222
PasswordAuthentication yes
PermitEmptyPasswords no
PermitRootLogin yes
SSHD_CONF

# Codespaces storage under /workspaces persists across normal stop/start and
# generally across container rebuilds. Keep host PRIVATE keys OUTSIDE the repo.
# If the Codespace is deleted, the private storage is also gone and the remote
# known_hosts fingerprint must be explicitly re-verified.
SSH_STATE=/workspaces/.bgdb-private/ssh-host-keys
install -d -o root -g root -m 0700 /workspaces/.bgdb-private "$SSH_STATE"
for algorithm in ed25519 rsa ecdsa; do
  key="ssh_host_${algorithm}_key"
  if [[ -s "$SSH_STATE/$key" && -s "$SSH_STATE/$key.pub" ]]; then
    install -o root -g root -m 0600 "$SSH_STATE/$key" "/etc/ssh/$key"
    install -o root -g root -m 0644 "$SSH_STATE/$key.pub" "/etc/ssh/$key.pub"
  fi
done
ssh-keygen -A >/dev/null
for algorithm in ed25519 rsa ecdsa; do
  key="ssh_host_${algorithm}_key"
  if [[ -s "/etc/ssh/$key" && ! -e "$SSH_STATE/$key" ]]; then
    install -o root -g root -m 0600 "/etc/ssh/$key" "$SSH_STATE/$key"
    install -o root -g root -m 0644 "/etc/ssh/$key.pub" "$SSH_STATE/$key.pub"
  fi
done

/usr/sbin/sshd -t
effective_port="$(/usr/sbin/sshd -T | awk '$1 == "port" { print $2; exit }')"
if [[ "$effective_port" != 2222 ]]; then
  echo "BGDB SSH CONFIG ERROR: expected effective port 2222, got ${effective_port:-missing}" >&2
  exit 1
fi
service ssh reload >/dev/null 2>&1 || service ssh start >/dev/null 2>&1 || /usr/sbin/sshd

# Tailscale Codespaces feature normally installs the client.
if ! command -v tailscale >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
    -o /etc/apt/sources.list.d/tailscale.list
  apt-get update
  apt-get install -y --no-install-recommends tailscale
fi

if ! pgrep -x tailscaled >/dev/null 2>&1; then
  if ! service tailscaled start >/dev/null 2>&1; then
    install -d -m 0700 /var/lib/tailscale
    nohup "$(command -v tailscaled)" --state=/var/lib/tailscale/tailscaled.state \
      >/tmp/bgdb-tailscaled.log 2>&1 </dev/null &
  fi
fi

# Keep the previously configured interactive setup for passwords and login.
while IFS=: read -r account _ uid _ _ home shell; do
  if [[ "$uid" -ge 1000 && "$uid" -lt 60000 ]] 2>/dev/null && [[ -f "$home/.bashrc" ]]; then
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

echo "BGDB SSH restored on private port 2222; host keys restored or saved to persistent Codespace storage."
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | sed 's/^/BGDB SSH host fingerprint: /'
