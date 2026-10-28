#!/usr/bin/env bash
# BGDB Codespace: start stable Tailscale Funnel for authenticated local BGSSH MCP.
# Never expose SSH port 2222 or publish a GitHub Codespaces public forwarding URL.
# Funnel URL is derived from the existing Tailscale node identity; no secret printed.
set -Eeuo pipefail
if [[ "$(id -un)" != vscode ]]; then
  echo "[BGSSH Funnel] Must run as vscode (postStartCommand)." >&2
  exit 1
fi
command -v tailscale >/dev/null || { echo "[BGSSH Funnel] Tailscale CLI missing." >&2; exit 1; }

BASE=http://127.0.0.1:8765
TOKEN_FILE="$HOME/.codex/bgssh-http-token"
if [[ ! -s "$TOKEN_FILE" || -L "$TOKEN_FILE" ]]; then
  echo "[BGSSH Funnel] MCP token absent or invalid path; refusing to publish." >&2
  exit 1
fi
if [[ "$(stat -c %a "$TOKEN_FILE")" != 600 || ! -O "$TOKEN_FILE" ]]; then
  echo "[BGSSH Funnel] Private token ownership/mode is not safe." >&2
  exit 1
fi
health="$(curl -fsS --max-time 3 "$BASE/health" 2>/dev/null || true)"
denied="$(curl -sS -X POST --max-time 3 -o /dev/null -w '%{http_code}' "$BASE/mcp" 2>/dev/null || true)"
if [[ "$health" != ok || "$denied" != 401 ]]; then
  echo "[BGSSH Funnel] MCP is not running with token protection; refusing to publish." >&2
  exit 1
fi

# An existing Tailscale node identity is kept in the named Codespaces volume.
# Do not run 'tailscale up' with a new authkey or reset the node here.
state="$(tailscale status --json | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState",""))')" || {
  echo "[BGSSH Funnel] Cannot read Tailscale state." >&2
  exit 1
}
if [[ "$state" != Running ]]; then
  echo "[BGSSH Funnel] Tailscale is not online (state=$state); use interactive tailscale login first." >&2
  exit 1
fi
dns="$(tailscale status --json | /usr/bin/python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName","").rstrip("."))')"
if [[ ! "$dns" =~ ^[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.ts\.net$ ]]; then
  echo "[BGSSH Funnel] No verified ts.net hostname for the current node; refusing to guess URL." >&2
  exit 1
fi

# Funnel publishes HTTPS on 443, reverse-proxying ONLY the local MCP 8765.
# --bg persists the setting across tailscaled restarts when state is preserved.
if ! sudo -n tailscale funnel --yes --bg --https=443 127.0.0.1:8765; then
  echo "[BGSSH Funnel] Funnel failed: check tailnet Funnel policy and HTTPS cert authorization." >&2
  echo "[BGSSH Funnel] Do not fall back to unauthenticated HTTP or a quick tunnel." >&2
  exit 1
fi

PUBLIC="https://$dns"
echo "[BGSSH Funnel] Configured URL: $PUBLIC"
echo "[BGSSH Funnel] Protected MCP path: $PUBLIC/<PRIVATE_TOKEN>/mcp (token omitted)"
echo "[BGSSH Funnel] The ChatGPT BGSSH app MCP URL must be updated manually once."
if [[ "$(curl -fsS --connect-timeout 4 --max-time 15 "$PUBLIC/health" 2>/dev/null || true)" == ok ]]; then
  code="$(curl -sS --connect-timeout 4 --max-time 15 -X POST -o /dev/null -w '%{http_code}' "$PUBLIC/mcp" 2>/dev/null || true)"
  if [[ "$code" == 401 ]]; then
    echo "[BGSSH Funnel] Public HTTPS reachable: /health=ok, unauthorized /mcp=401."
    exit 0
  fi
  echo "[BGSSH Funnel] Public HTTPS reached health, but auth status was HTTP $code (expected 401)." >&2
  exit 1
fi
echo "[BGSSH Funnel] Public URL not yet reachable: check Funnel DNS/certificate/policy propagation." >&2
exit 1
