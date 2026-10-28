#!/usr/bin/env bash
# BGDB: expose ONLY the authenticated BGSSH MCP port via GitHub Codespaces HTTPS.
# Run as vscode in the Codespace; no secrets are printed or added to Git.
# GitHub may reset public visibility to private after a Codespace restart.
set -Eeuo pipefail

if [[ "$(id -un)" != "vscode" ]]; then
  echo "[BGSSH HTTPS] Must run as vscode; no port visibility changed." >&2
  exit 1
fi

PORT=8765
BASE="http://127.0.0.1:$PORT"
TOKEN_FILE="$HOME/.codex/bgssh-http-token"
if [[ ! -s "$TOKEN_FILE" ]] || [[ -L "$TOKEN_FILE" ]]; then
  echo "[BGSSH HTTPS] Protected token not available; refusing public forwarding." >&2
  exit 1
fi
if [[ ! -O "$TOKEN_FILE" ]] || [[ "$(stat -c %a "$TOKEN_FILE")" != 600 ]]; then
  echo "[BGSSH HTTPS] Token must belong to vscode and have 0600 permissions." >&2
  exit 1
fi
# Confirm local backend and that a request with NO token gets denied.
health="$(curl -fsS --connect-timeout 2 --max-time 3 "$BASE/health" 2>/dev/null || true)"
denied="$(curl -sS --connect-timeout 2 --max-time 3 -X POST -o /dev/null -w '%{http_code}' "$BASE/mcp" 2>/dev/null || true)"
if [[ "$health" != ok || "$denied" != 401 ]]; then
  echo "[BGSSH HTTPS] Local backend / authentication is not ready; port stays private." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "[BGSSH HTTPS] GitHub CLI (gh) is not available; port stays private." >&2
  exit 1
fi
if [[ -z "${CODESPACE_NAME:-}" ]]; then
  echo "[BGSSH HTTPS] CODESPACE_NAME not set; refusing to select a different codespace." >&2
  exit 1
fi

# Codespaces automatically forwards the declared 8765 port once the editor
# connects; visibility can be changed after this registration is complete.
for attempt in 1 2 3 4 5 6; do
  if gh codespace ports -c "$CODESPACE_NAME" --json sourcePort --jq '.[].sourcePort' 2>/dev/null | grep -qx "$PORT"; then
    if gh codespace ports visibility "$PORT:public" -c "$CODESPACE_NAME" >/dev/null 2>&1; then
      # Verify public visibility from GitHub API state; no token is printed.
      vis="$(gh codespace ports -c "$CODESPACE_NAME" --json sourcePort,visibility --jq '.[] | select(.sourcePort == 8765) | .visibility' 2>/dev/null || true)"
      if [[ "$vis" == public ]]; then
        echo "[BGSSH HTTPS] GitHub Codespace port $PORT is PUBLIC (MCP remains token-protected)."
        echo "[BGSSH HTTPS] Public HTTPS base: https://${CODESPACE_NAME}-${PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
        echo "[BGSSH HTTPS] ChatGPT plugin's configured MCP URL must separately match this host."
        exit 0
      fi
    fi
  fi
  sleep 5
done

echo "[BGSSH HTTPS] Unable to publish port; verify gh authentication/port policy/forwarding. It may still be private." >&2
exit 1
