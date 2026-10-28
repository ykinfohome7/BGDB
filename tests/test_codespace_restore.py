"""Offline guardrails for BGDB Codespace auto-restore (no secrets and no network)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / ".devcontainer"
cfg = json.loads((DIR / "devcontainer.json").read_text())
assert cfg["remoteUser"] == "vscode"
assert "restore-on-start.sh" in cfg["postStartCommand"]
mounts = cfg["mounts"]
for required in (
    "target=/home/vscode/.claude,",
    "target=/home/vscode/.codex,",
    "target=/home/vscode/.local/share/bgdb-ai-tools,",
    "target=/var/lib/bgdb-ssh-hostkeys,",
    "target=/var/lib/tailscale,",
):
    assert any(required in m for m in mounts), required
assert "ghcr.io/devcontainers/features/node:1" in cfg["features"]

setup = (DIR / "setup-bgadmin.sh").read_text()
assert "Port 2222" in setup and "sshd -t" in setup
assert 'SSH_KEY_STORE=/var/lib/bgdb-ssh-hostkeys' in setup
assert 'install -m 0600' in setup
assert "ssh-keygen -A" in setup
assert 'sshd -T' in setup

first_run = (DIR / "finish-bgdb-setup.sh").read_text()
assert "port 2222" in first_run
assert "tee /etc/ssh/sshd_config.d/00-bgdb-password.conf" not in first_run

restore = (DIR / "restore-on-start.sh").read_text()
assert 'setup-bgadmin.sh' in restore and 'setup-ai-tools.sh' in restore
assert 'tailscale ip -4' in restore
assert "No DNS A record or HTTPS certificate was changed" in restore
assert "Port 2222" in setup and "bgssh.abrdns.com" in restore

ai = (DIR / "setup-ai-tools.sh").read_text()
assert "BGDB_AI_UPDATE" in ai
assert '@openai/codex @anthropic-ai/claude-code' in ai
assert "Reusing persistent Claude Code + Codex installation." in ai

print("BGDB Codespace auto-restore static safety tests PASSED")
