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

# Inspect the complete Serve/Funnel config before touching any existing port.
# A listener on 443 may belong to another application. Do not reset it.
ROOT=/workspaces/BGDB/.devcontainer
HELPER="$ROOT/check-bgssh-funnel-config.py"
if [[ ! -r "$HELPER" ]]; then
  echo "[BGSSH Funnel] Missing safe listener classifier: $HELPER" >&2
  exit 1
fi
get_listener_states() {
  local cfg
  cfg="$(sudo -n tailscale serve status --json 2>/dev/null)" || {
    echo "[BGSSH Funnel] Cannot inspect Tailscale Serve/Funnel configuration; refusing changes." >&2
    return 1
  }
  printf '%s' "$cfg" | /usr/bin/python3 "$HELPER"
}
states="$(get_listener_states)" || exit 1
read -r state443 state8443 < <(
  /usr/bin/python3 -c 'import json,sys; x=json.loads(sys.argv[1]); print(x["443"], x["8443"])' "$states"
)
echo "[BGSSH Funnel] HTTPS 443: $state443; HTTPS 8443: $state8443"

if [[ "$state443" == match ]]; then
  PORT=443
  echo "[BGSSH Funnel] Reusing existing authenticated Funnel on HTTPS 443."
elif [[ "$state8443" == match ]]; then
  PORT=8443
  echo "[BGSSH Funnel] Reusing existing authenticated Funnel on HTTPS 8443."
else
  if [[ "$state443" == free ]]; then
    PORT=443
  elif [[ "$state8443" == free ]]; then
    PORT=8443
    echo "[BGSSH Funnel] Preserving existing HTTPS 443 service; using HTTPS 8443 for BGSSH."
  else
    echo "[BGSSH Funnel] Both HTTPS 443 and 8443 are occupied by other routes. Nothing changed." >&2
    exit 1
  fi

  if ! sudo -n tailscale funnel --yes --bg --https="$PORT" 127.0.0.1:8765 >/dev/null 2>&1; then
    if [[ "$PORT" == 443 && "$state8443" == free ]]; then
      echo "[BGSSH Funnel] 443 is unavailable; trying separate HTTPS 8443 without resetting it."
      PORT=8443
      sudo -n tailscale funnel --yes --bg --https=8443 127.0.0.1:8765 >/dev/null 2>&1 || {
        echo "[BGSSH Funnel] Cannot configure 8443; check sudo, Funnel policy, certificates and listener status." >&2
        exit 1
      }
    else
      echo "[BGSSH Funnel] Cannot configure HTTPS $PORT; check sudo, Funnel policy and listener status." >&2
      exit 1
    fi
  fi
  # The command can be accepted without a public relay being ready yet.
  # Confirm it is still OUR Funnel and not an existing Serve-only route.
  states="$(get_listener_states)" || exit 1
  selected_state="$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2],"unknown"))' "$states" "$PORT")"
  if [[ "$selected_state" != match ]]; then
    echo "[BGSSH Funnel] HTTPS $PORT did not become an exclusive BGSSH Funnel; refusing to report success." >&2
    exit 1
  fi
fi

if [[ "$PORT" == 443 ]]; then
  PUBLIC="https://$dns"
else
  PUBLIC="https://$dns:$PORT"
fi
mkdir -p "$HOME/.cache/bgdb"
printf '%s\n' "$PUBLIC" > "$HOME/.cache/bgdb/bgssh-funnel-public-url"
chmod 600 "$HOME/.cache/bgdb/bgssh-funnel-public-url"
echo "[BGSSH Funnel] Configured public base: $PUBLIC"
echo "[BGSSH Funnel] Protected MCP path: $PUBLIC/<PRIVATE_TOKEN>/mcp (token omitted)"
echo "[BGSSH Funnel] Update the ChatGPT BGSSH MCP URL manually; never paste the private token in chat."

public_health="$(curl -fsS --connect-timeout 4 --max-time 15 "$PUBLIC/health" 2>/dev/null || true)"
if [[ "$public_health" == ok ]]; then
  code="$(curl -sS --connect-timeout 4 --max-time 15 -X POST -o /dev/null -w '%{http_code}' "$PUBLIC/mcp" 2>/dev/null || true)"
  if [[ "$code" == 401 ]]; then
    echo "[BGSSH Funnel] HTTPS verified FROM CODESPACE: health=ok, unauthenticated /mcp=401."
    echo "[BGSSH Funnel] Checking PUBLIC DNS independently of tailnet MagicDNS."
    DNS_CHECK=/workspaces/BGDB/.devcontainer/check-bgssh-public-dns.py
    if [[ ! -r "$DNS_CHECK" ]]; then
      echo "[BGSSH Funnel] Public DNS checker missing; Internet reachability unverified." >&2
      exit 1
    fi
    if /usr/bin/python3 "$DNS_CHECK" "$dns"; then
      echo "[BGSSH Funnel] Public DNS records exist (does not guarantee ChatGPT can connect)."
      exit 0
    fi
    echo "[BGSSH Funnel] Public DNS unavailable or unverified; possible Tailscale Funnel DNS incident." >&2
    echo "[BGSSH Funnel] Local service is still healthy; do not reset Funnel or change the MCP token." >&2
    exit 1
  fi
  echo "[BGSSH Funnel] HTTPS reachable but authentication response was HTTP $code (expected 401)." >&2
  exit 1
fi
echo "[BGSSH Funnel] Funnel is configured, but public HTTPS cannot be verified." >&2
echo "[BGSSH Funnel] Check public ts.net DNS propagation and Tailscale Funnel service status." >&2
exit 1
