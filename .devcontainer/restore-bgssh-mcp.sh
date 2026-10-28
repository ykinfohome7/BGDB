#!/usr/bin/env bash
# Restore local BGSSH MCP for Claude Code and Codex inside the BGDB Codespace.
# Does not open public ports, publish DNS, or copy HTTPS certificate private keys.
set -Eeuo pipefail

# sudo -u vscode -H bash -c does not source ~/.bashrc: restore local CLI PATH.
export PATH="$HOME/.local/bin:$PATH"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script as the Codespace vscode user (not root)." >&2
  exit 1
fi
sudo -n true >/dev/null 2>&1 || { echo "Noninteractive sudo is required."; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is not installed."; exit 1; }
command -v ssh-keygen >/dev/null 2>&1 || { echo "OpenSSH client is not installed."; exit 1; }

REPO="$HOME/.local/share/bgdb-ssh-connector"
REMOTE="https://github.com/ykinfohome7/ssh-connector.git"
mkdir -p "$(dirname "$REPO")" "$HOME/.ssh" "$HOME/.ssh-connector"
chmod 700 "$HOME/.ssh" "$HOME/.ssh-connector"

if [[ ! -d "$REPO/.git" ]]; then
  git clone --depth 1 "$REMOTE" "$REPO"
else
  origin="$(git -C "$REPO" remote get-url origin || true)"
  [[ "$origin" == "$REMOTE" ]] || { echo "Existing BGSSH repository has a different origin; refusing to replace."; exit 1; }
  # Retain local changes, including locally tested fixes, rather than overwriting them.
  if [[ -z "$(git -C "$REPO" status --porcelain)" ]]; then
    git -C "$REPO" pull --ff-only
  else
    echo "Local BGSSH checkout has changes; preserving it without updating."
  fi
fi

runner="$REPO/plugins/ssh-connector/bin/run.sh"
[[ -f "$runner" ]] || { echo "BGSSH MCP launcher is missing."; exit 1; }

# Create a local-only identity for vscode -> bgadmin over 127.0.0.1:2222.
# SSH host public key is read directly from the same container; NO blind ssh-keyscan.
identity="$HOME/.ssh/bgdb_codespace_ed25519"
if [[ ! -s "$identity" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C "bgdb-codespace-local" -f "$identity"
fi
chmod 600 "$identity"
local_pub="$(cat "$identity.pub")"
sudo -n install -d -m 700 -o bgadmin -g bgadmin /home/bgadmin/.ssh
sudo -n touch /home/bgadmin/.ssh/authorized_keys
sudo -n chown bgadmin:bgadmin /home/bgadmin/.ssh/authorized_keys
sudo -n chmod 600 /home/bgadmin/.ssh/authorized_keys
if ! printf '%s\n' "$local_pub" | sudo -n grep -Fqx -f /dev/stdin /home/bgadmin/.ssh/authorized_keys; then
  printf '%s\n' "$local_pub" | sudo -n tee -a /home/bgadmin/.ssh/authorized_keys >/dev/null
fi

server_pub="$(sudo -n cat /etc/ssh/ssh_host_ed25519_key.pub)"
type_and_key="$(printf '%s\n' "$server_pub" | awk '{print $1 " " $2}')"
case "$type_and_key" in
  'ssh-ed25519 '*) ;;
  *) echo "Invalid local SSH host key."; exit 1 ;;
esac
known="$HOME/.ssh/bgdb-local-known_hosts"
printf '[127.0.0.1]:2222 %s\n' "$type_and_key" > "$known"
chmod 600 "$known"

# Never replace an existing user-managed server list.
cfg="$HOME/.ssh-connector/servers.yaml"
if [[ ! -e "$cfg" ]]; then
  cat > "$cfg" <<YAML
defaults:
  known_hosts: $known
  connect_timeout: 8
  retries: 2
  command_timeout: 180
servers:
  BGDB-Codespace:
    os: debian
    user: bgadmin
    hosts: [127.0.0.1]
    port: 2222
    key: $identity
    known_hosts: $known
    tags: [codespaces, local, ssh]
YAML
  chmod 600 "$cfg"
else
  echo "Existing ~/.ssh-connector/servers.yaml retained without changes."
fi

# Register for both coding agents. Do not attempt CLI login here; authentication
# is performed by the owner and is retained in the configured user storage.
if command -v claude >/dev/null 2>&1; then
  if claude mcp get bgssh >/dev/null 2>&1; then
    echo "Claude Code: BGSSH MCP already registered."
  elif claude mcp add --scope user bgssh -- sh "$runner"; then
    echo "Claude Code: BGSSH MCP registered."
  else
    echo "WARNING: Claude Code MCP registration failed." >&2
  fi
else
  echo "WARNING: Claude Code CLI not available." >&2
fi

if command -v codex >/dev/null 2>&1; then
  if codex mcp get bgssh >/dev/null 2>&1; then
    echo "Codex: BGSSH MCP already registered."
  elif codex mcp add bgssh -- sh "$runner"; then
    echo "Codex: BGSSH MCP registered."
  else
    echo "WARNING: Codex MCP registration failed." >&2
  fi
else
  echo "WARNING: Codex CLI not available." >&2
fi

# Actual local SSH test is key-based and checks the stored local SSH fingerprint.
if ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known" \
    -o "IdentitiesOnly=yes" -i "$identity" -p 2222 -o ConnectTimeout=4 \
    bgadmin@127.0.0.1 'id -un' 2>/dev/null | grep -qx bgadmin; then
  echo "BGDB local SSH: 127.0.0.1:2222 successfully authenticated as bgadmin."
else
  echo "WARNING: SSH test on 127.0.0.1:2222 failed; verify SSH service and key." >&2
  exit 1
fi
echo "BGSSH restored for local Claude Code / Codex; remote GitHub Actions HTTPS is separate."
