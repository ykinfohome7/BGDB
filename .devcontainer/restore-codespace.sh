#!/usr/bin/env bash
# GitHub Codespaces postStart: restore BGDB private SSH port 2222 and AI tools.
# Non-interactive, idempotent, runs on every Codespace start/resume.
set -uo pipefail
ROOT=/workspaces/BGDB
LOG="$HOME/.cache/bgdb/codespace-restore.log"
mkdir -p "$(dirname "$LOG")"
umask 077
: > "$LOG"

echo "[BGDB] Restoring Codespace (SSH 2222, Tailscale, Claude, Codex, BGSSH)..."

failed=0
run_step() {
  local label="$1"
  shift
  printf '[BGDB] %s...\n' "$label"
  if "$@" >>"$LOG" 2>&1; then
    printf '[BGDB] OK: %s\n' "$label"
  else
    printf '[BGDB] WARNING: %s failed; see %s\n' "$label" "$LOG" >&2
    failed=1
  fi
}

if [[ ! -f "$ROOT/.devcontainer/setup-bgadmin.sh" ]]; then
  echo "[BGDB] ERROR: missing workspace at $ROOT" >&2
  exit 1
fi

run_step "Restore private SSH 2222, stable host keys and Tailscale daemon" \
  sudo -n bash "$ROOT/.devcontainer/setup-bgadmin.sh"

export PATH="$HOME/.local/bin:$PATH"
if ! command -v claude >/dev/null 2>&1 || ! command -v codex >/dev/null 2>&1; then
  run_step "Install missing Claude Code and Codex CLI" \
    bash "$ROOT/.devcontainer/setup-ai-tools.sh"
else
  echo "[BGDB] OK: Claude Code and Codex already installed."
fi

# Only register MCP after the SSH daemon and local credentials are ready.
run_step "Restore local BGSSH MCP for Claude Code and Codex" \
  bash "$ROOT/.devcontainer/restore-bgssh-mcp.sh"

# Start the separately authenticated HTTP MCP endpoint on localhost only.
# GitHub Codespaces forwards port 8765 privately by default; never make it public here.
run_step "Start private authenticated BGSSH MCP HTTP (127.0.0.1:8765)" \
  bash "$ROOT/.devcontainer/start-bgssh-http.sh"

if tailscale ip -4 >/dev/null 2>&1; then
  echo "[BGDB] OK: Tailscale private IPv4 present."
else
  echo "[BGDB] ACTION: Tailscale is not authenticated. Login may be needed in a terminal."
  # Do NOT echo or request tokens in logs. Existing interactive first-run
  # setup handles Tailscale user authorization.
fi

if [[ "$failed" -ne 0 ]]; then
  echo "[BGDB] One or more restore steps need attention. Inspect: $LOG"
else
  echo "[BGDB] Codespace restore completed. SSH=2222; HTTPS certificate remains separate."
fi

# Do not block VS Code startup when offline CLI downloads are temporarily
# unavailable. Manual rerun and logs allow diagnosis after the environment opens.
exit 0
