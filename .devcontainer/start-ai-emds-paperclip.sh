#!/usr/bin/env bash
# BGDB AI-EMDS: изпълнява се като bgadmin, без root и без публичен порт.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/share/nvm/current/bin:$HOME/.local/bin:$PATH"
REPO="$HOME/ai-engineering-dispatch"
REMOTE="https://github.com/ykinfohome7/ai-engineering-dispatch.git"
STATE="$HOME/.local/state/bgdb-ai-emds"
mkdir -p "$STATE"
# Някои AI инструменти използват временни файлове; избягвай общата /tmp/opencode.
TMPROOT="$HOME/.cache/bgdb-ai-emds/tmp"
mkdir -p -m 700 "$TMPROOT"
export TMPDIR="$TMPROOT"
exec 9>"$STATE/bootstrap.lock"
if ! flock -n 9; then
  echo "[AI-EMDS] Another bootstrap is running; skipping."
  exit 0
fi

# Запазва локалните промени; не обновява main без независим преглед.
if [[ ! -e "$REPO" ]]; then
  GIT_TERMINAL_PROMPT=0 git clone --branch main --single-branch "$REMOTE" "$REPO"
elif [[ ! -d "$REPO/.git" ]]; then
  echo "[AI-EMDS] Existing path is not a Git repository; refusing overwrite." >&2
  exit 1
fi
origin="$(git -C "$REPO" remote get-url origin)"
if [[ "$origin" != "$REMOTE" && "$origin" != "https://github.com/ykinfohome7/ai-engineering-dispatch" ]]; then
  echo "[AI-EMDS] Unexpected Git origin; refusing changes." >&2
  exit 1
fi
git -C "$REPO" submodule update --init --recursive
PAPERCLIP="$REPO/dispatcher/paperclip"
[[ -f "$PAPERCLIP/package.json" && -f "$PAPERCLIP/pnpm-lock.yaml" ]] || {
  echo "[AI-EMDS] Paperclip submodule is not initialized." >&2; exit 1;
}
command -v node >/dev/null || { echo "[AI-EMDS] Node.js missing" >&2; exit 1; }
node -e 'const [a,b]=process.versions.node.split(".").map(Number); if(a<24||(a===24&&b<11)) process.exit(1)' || {
  echo "[AI-EMDS] Node >=24.11 required." >&2; exit 1;
}
command -v corepack >/dev/null || { echo "[AI-EMDS] Corepack missing" >&2; exit 1; }

cd "$PAPERCLIP"
# Corepack чете packageManager и използва фиксирания pnpm 9.15.4.
locksha="$(sha256sum pnpm-lock.yaml | cut -d' ' -f1)"
oldsha="$(cat "$STATE/installed-lock.sha256" 2>/dev/null || true)"
if [[ ! -f node_modules/.modules.yaml || "$locksha" != "$oldsha" ]]; then
  echo "[AI-EMDS] Installing pinned Paperclip dependencies (first run/update)."
  corepack pnpm install --frozen-lockfile
  printf '%s\n' "$locksha" > "$STATE/installed-lock.sha256"
else
  echo "[AI-EMDS] Paperclip dependencies already installed."
fi

# Не спирай или заменяй неизвестен процес на порт 3100.
if curl --silent --fail --max-time 3 http://127.0.0.1:3100/api/health >/dev/null 2>&1; then
  echo "[AI-EMDS] Paperclip responds at private localhost:3100."
  exit 0
fi
if ss -ltn 2>/dev/null | grep -Eq '127\.0\.0\.1:3100|0\.0\.0\.0:3100|\[::\]:3100'; then
  echo "[AI-EMDS] Port 3100 is occupied; refusing to launch a second server." >&2
  exit 1
fi
if [[ -s "$STATE/paperclip.pid" ]]; then
  prev="$(cat "$STATE/paperclip.pid")"
  if [[ "$prev" =~ ^[0-9]+$ ]] && kill -0 "$prev" 2>/dev/null; then
    echo "[AI-EMDS] Previous Paperclip launcher is alive; check log."
    exit 0
  fi
fi

# Логът е частен; не поставяй API токени в runtime променливи на публично място.
LOG="$STATE/paperclip.log"
touch "$LOG"
chmod 600 "$LOG"
PAPERCLIP_TELEMETRY_DISABLED=1 NODE_OPTIONS="--max-old-space-size=4096" \
  nohup corepack pnpm dev >>"$LOG" 2>&1 </dev/null &
pid=$!
printf '%s\n' "$pid" > "$STATE/paperclip.pid"
sleep 3
if kill -0 "$pid" 2>/dev/null; then
  echo "[AI-EMDS] Paperclip started (PID recorded). Port 3100 must stay PRIVATE."
else
  echo "[AI-EMDS] Paperclip startup exited. Inspect private log: $LOG" >&2
  exit 1
fi
