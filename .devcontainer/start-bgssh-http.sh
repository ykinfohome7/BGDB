#!/usr/bin/env bash
# Start the BGSSH streamable HTTP MCP backend inside GitHub Codespaces.
# Private by default: bind only 127.0.0.1; Codespaces port visibility is managed separately.
# Token is persisted in the existing private vscode ~/.codex Docker volume, NEVER in Git.
set -Eeuo pipefail
umask 077

if [[ "$(id -un)" != "vscode" ]]; then
  echo "[BGSSH] Run as the Codespace 'vscode' user (not root or bgadmin)." >&2
  exit 1
fi

APP="$HOME/.local/share/bgdb-ssh-connector/plugins/ssh-connector/bin/run.sh"
CFG="$HOME/.ssh-connector/servers.yaml"
TOKEN_FILE="$HOME/.codex/bgssh-http-token"
LOG_DIR="$HOME/.cache/bgdb"
LOG="$LOG_DIR/bgssh-http.log"
PIDFILE="$LOG_DIR/bgssh-http.pid"
PORT=8765
URL="http://127.0.0.1:$PORT"

[[ -f "$APP" ]] || { echo "[BGSSH] Connector not installed: run restore-bgssh-mcp.sh first." >&2; exit 1; }
[[ -s "$CFG" ]] || { echo "[BGSSH] Missing local SSH config: run restore-bgssh-mcp.sh first." >&2; exit 1; }
command -v python3 >/dev/null || { echo "[BGSSH] python3 missing." >&2; exit 1; }
command -v curl >/dev/null || { echo "[BGSSH] curl missing." >&2; exit 1; }

mkdir -p "$HOME/.codex" "$LOG_DIR"
chmod 700 "$LOG_DIR"

# Named Docker volumes may initially be owned by root after a Codespace rebuild.
# Repair ONLY the Codex volume's mount directory and (if present) this one token.
# Never recursively chown the volume or change existing Codex credentials.
if [[ -L "$HOME/.codex" || -L "$TOKEN_FILE" ]]; then
  echo "[BGSSH] Refusing symlinked Codex token directory/file." >&2
  exit 1
fi
if [[ ! -O "$HOME/.codex" || ! -w "$HOME/.codex" ]]; then
  echo "[BGSSH] Repairing ownership of the Codex token volume for vscode."
  sudo -n chown vscode:vscode "$HOME/.codex" || {
    echo "[BGSSH] Could not repair ~/.codex ownership; run: sudo chown vscode:vscode /home/vscode/.codex" >&2
    exit 1
  }
fi
chmod 700 "$HOME/.codex"
if [[ -e "$TOKEN_FILE" && ! -O "$TOKEN_FILE" ]]; then
  sudo -n chown vscode:vscode "$TOKEN_FILE" || {
    echo "[BGSSH] Could not repair private token ownership." >&2
    exit 1
  }
fi

if [[ ! -s "$TOKEN_FILE" ]]; then
  # Linux kernel CSPRNG: 32 random bytes, formatted as a 64-digit hex token.
  # Using coreutils avoids broken/incomplete Python stdlib environments.
  (head -c 32 /dev/urandom | od -An -tx1 | tr -d '[:space:]') > "$TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"
if [[ ! "$TOKEN" =~ ^[a-f0-9]{64}$ ]]; then
  echo "[BGSSH] Refusing malformed token; inspect your private ~/.codex/bgssh-http-token" >&2
  exit 1
fi
unset TOKEN

# A previously started listener is good only if both health and auth checks pass.
health="$(curl -fsS --connect-timeout 2 --max-time 3 "$URL/health" 2>/dev/null || true)"
code="$(curl -sS --connect-timeout 2 --max-time 3 -X POST -o /dev/null -w '%{http_code}' "$URL/mcp" 2>/dev/null || true)"
if [[ "$health" == "ok" && "$code" == "401" ]]; then
  echo "[BGSSH] MCP already running on 127.0.0.1:$PORT (protected HTTP 401)."
  exit 0
fi
if [[ "$code" != "000" && -n "$code" ]]; then
  echo "[BGSSH] Port $PORT is occupied by an unexpected HTTP service (HTTP $code); refusing to replace it." >&2
  exit 1
fi

# Validate the system Python before launching the connector.
# Python -I ignores PYTHONPATH/PYTHONHOME and user site packages.
if ! /usr/bin/python3 -I -c 'import secrets, venv, ssl' >/dev/null 2>&1; then
  echo "[BGSSH] Python 3.13 standard library/venv is missing or damaged." >&2
  echo "[BGSSH] Repair in Debian: sudo apt-get update && sudo apt-get install -y --reinstall libpython3.13-stdlib python3.13-venv" >&2
  exit 1
fi

# Do NOT put the token on the command line, in public logs, or in the repository.
# Running as vscode provides the local SSH key and its pinned known_hosts file.
nohup bash -c '
  set -Eeuo pipefail
  export SSH_CONNECTOR_TOKEN="$(cat "$HOME/.codex/bgssh-http-token")"
  export SSH_CONNECTOR_CONFIG="$HOME/.ssh-connector/servers.yaml"
  # GitHub contents uploads may not carry the executable mode bit.
  # Invoke through sh; never require chmod on the cloned repository.
  exec sh "$HOME/.local/share/bgdb-ssh-connector/plugins/ssh-connector/bin/run.sh" --http --host 127.0.0.1 --port 8765
' > "$LOG" 2>&1 </dev/null &
echo "$!" > "$PIDFILE"

for attempt in $(seq 1 90); do
  health="$(curl -fsS --connect-timeout 1 --max-time 2 "$URL/health" 2>/dev/null || true)"
  code="$(curl -sS --connect-timeout 1 --max-time 2 -X POST -o /dev/null -w '%{http_code}' "$URL/mcp" 2>/dev/null || true)"
  if [[ "$health" == "ok" && "$code" == "401" ]]; then
    echo "[BGSSH] MCP running on 127.0.0.1:$PORT, unauthenticated POST=401."
    echo "[BGSSH] GitHub Ports tab: forward 8765, keep PRIVATE until authentication is verified."
    echo "[BGSSH] HTTPS address (only after forwarding): https://${CODESPACE_NAME:-CODESPACE_NAME}-8765.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
    exit 0
  fi
  if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "[BGSSH] MCP process exited; inspect local $LOG (do not paste secrets)." >&2
    exit 1
  fi
  sleep 2
done

echo "[BGSSH] MCP did not become ready; inspect local $LOG (do not paste secrets)." >&2
exit 1
