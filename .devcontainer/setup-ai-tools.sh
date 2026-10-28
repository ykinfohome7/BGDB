#!/usr/bin/env bash
set -Eeuo pipefail

# BGDB Codespaces: install both CLIs without changing nvm's global npm prefix.
# This runs only inside the Codespace, never on the user's own servers.
TOOLS_DIR="$HOME/.local/share/bgdb-ai-tools"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$TOOLS_DIR" "$BIN_DIR"

# Repair settings left by an earlier BGDB script. nvm does not support an
# explicit global npm prefix in ~/.npmrc. Leave unrelated npmrc entries intact.
if [ -f "$HOME/.npmrc" ]; then
  sed -i -E '/^[[:space:]]*(prefix|globalconfig)[[:space:]]*=/d' "$HOME/.npmrc"
fi
unset NPM_CONFIG_PREFIX npm_config_prefix NPM_CONFIG_GLOBALCONFIG npm_config_globalconfig || true

# The node feature can provide nvm as well as node/npm.
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.nvm/nvm.sh"
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js/npm missing: Rebuild Codespace to apply the Node LTS devcontainer feature." >&2
  exit 2
fi
echo "Node: $(node --version)"
echo "npm: $(npm --version)"

# Reuse packages from the persistent volume after stop/start or rebuild.
# Upgrade intentionally with BGDB_AI_UPDATE=1, not on every boot.
if [ "${BGDB_AI_UPDATE:-0}" = 1 ] ||
   [ ! -x "$TOOLS_DIR/node_modules/.bin/codex" ] ||
   [ ! -x "$TOOLS_DIR/node_modules/.bin/claude" ]; then
  npm install --prefix "$TOOLS_DIR" --no-audit --no-fund @openai/codex @anthropic-ai/claude-code
else
  echo "Reusing persistent Claude Code + Codex installation."
fi

for tool in codex claude; do
  if [ ! -x "$TOOLS_DIR/node_modules/.bin/$tool" ]; then
    echo "Installation did not provide: $tool" >&2
    exit 1
  fi
  ln -sfn "$TOOLS_DIR/node_modules/.bin/$tool" "$BIN_DIR/$tool"
done

# Remove legacy PATH entry from the first Codespaces setup.
if [ -f "$HOME/.bashrc" ]; then
  sed -i '/^# BGDB_CODESPACES_NPM$/,+1d' "$HOME/.bashrc"
fi
if ! grep -Fq 'BGDB_CODESPACES_BIN' "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# BGDB_CODESPACES_BIN\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
fi
export PATH="$BIN_DIR:$PATH"

printf '\nCodex: '
codex --version
printf 'Claude Code: '
claude --version
printf '\nInstalled. Next: run codex and claude to authenticate interactively.\n'
