#!/usr/bin/env bash
# Non-secret BGSSH service and Funnel diagnostic for GitHub Codespaces.
# Produces only status codes, public hostnames and versions.
set -uo pipefail
BASE=http://127.0.0.1:8765
echo "=== BGSSH LOCAL ==="
if [[ -r "$HOME/.local/share/bgdb-ssh-connector/VERSION" ]]; then
  printf 'Installed checkout version: '
  cat "$HOME/.local/share/bgdb-ssh-connector/VERSION"
fi
if [[ -r "$HOME/.cache/bgdb/bgssh-http.git-sha" ]]; then
  printf 'Started checkout commit: '
  cat "$HOME/.cache/bgdb/bgssh-http.git-sha"
fi
curl -sS --connect-timeout 2 --max-time 4 -o /dev/null -w 'Local health HTTP %{http_code}\n' "$BASE/health" || true
curl -sS --connect-timeout 2 --max-time 4 -X POST -o /dev/null -w 'Local unauth MCP HTTP %{http_code}\n' "$BASE/mcp" || true
echo "=== TAILSCALE ==="
if ! command -v tailscale >/dev/null 2>&1; then
  echo 'Tailscale CLI unavailable'
  exit 1
fi
state="$(tailscale status --json 2>/dev/null | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState","unknown"))' 2>/dev/null || echo unavailable)"
dns="$(tailscale status --json 2>/dev/null | /usr/bin/python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName","").rstrip("."))' 2>/dev/null || true)"
echo "Tailscale backend state: $state"
# Tailscale may omit Self.DNSName for an unprivileged status query.
# Prefer the previously verified, locally saved Funnel public base URL.
SAVED="$HOME/.cache/bgdb/bgssh-funnel-public-url"
BASE_PUBLIC=""
if [[ -r "$SAVED" && ! -L "$SAVED" ]]; then
  candidate="$(cat "$SAVED" 2>/dev/null || true)"
  if [[ "$candidate" =~ ^https://[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.ts\.net(:8443)?$ ]]; then
    BASE_PUBLIC="$candidate"
    dns="${candidate#https://}"
    dns="${dns%:8443}"
    echo "Using saved Funnel hostname (Tailscale status DNSName may be empty)."
  fi
fi
if [[ -z "$BASE_PUBLIC" && "$dns" =~ ^[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.ts\.net$ ]]; then
  BASE_PUBLIC="https://$dns"
fi

if [[ -n "$BASE_PUBLIC" ]]; then
  echo "Tailscale HTTPS hostname: $dns"
  echo "=== EXTERNAL PUBLIC DNS (NOT MAGICDNS) ==="
  DNS_CHECK=/workspaces/BGDB/.devcontainer/check-bgssh-public-dns.py
  if [[ -r "$DNS_CHECK" ]]; then
    /usr/bin/python3 "$DNS_CHECK" "$dns" || true
  else
    echo "External DNS verifier is missing."
  fi
  echo "=== FUNNEL HTTPS (AS SEEN FROM CODESPACE) ==="
  echo "Configured HTTPS base: $BASE_PUBLIC"
  curl -sS --connect-timeout 5 --max-time 12 -o /dev/null -w 'Public health HTTP %{http_code}\n' "$BASE_PUBLIC/health" || true
  curl -sS --connect-timeout 5 --max-time 12 -X POST -o /dev/null -w 'Public unauth MCP HTTP %{http_code}\n' "$BASE_PUBLIC/mcp" || true
  echo "NOTE: HTTPS from inside the tailnet does not prove public Internet reachability."
  echo "BGSSH ChatGPT URL format: $BASE_PUBLIC/<PRIVATE_TOKEN>/mcp"
else
  echo "No usable ts.net hostname from Tailscale status or saved Funnel URL."
fi
echo "=== FUNNEL CONFIG (SAFE SUMMARY) ==="
if cfg="$(sudo -n tailscale serve status --json 2>/dev/null)" && [[ -r /workspaces/BGDB/.devcontainer/check-bgssh-funnel-config.py ]]; then
  printf '%s' "$cfg" | /usr/bin/python3 /workspaces/BGDB/.devcontainer/check-bgssh-funnel-config.py || true
else
  echo "Cannot inspect Serve/Funnel status."
fi
echo "=== BOOT LOG (NO TOKENS) ==="
if [[ -r "$HOME/.cache/bgdb/codespace-restore.log" ]]; then
  grep -E '^\[BGSSH( Funnel)?\]|^\[BGDB\]' "$HOME/.cache/bgdb/codespace-restore.log" | tail -n 20 | sed -E 's#/[0-9a-f]{48,}/#/<REDACTED>/#g' || true
fi
