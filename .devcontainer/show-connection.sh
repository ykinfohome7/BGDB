#!/usr/bin/env bash
# Show Codespaces identity and safe private SSH connection commands.
cs="${CODESPACE_NAME:-unknown}"
ssh_port="$(sudo -n /usr/sbin/sshd -T 2>/dev/null | awk '$1 == \"port\" {print $2; exit}' || true)"
ssh_port="${ssh_port:-2222}"
printf 'Detected SSH port: %s\n' "$ssh_port"
printf '\n========== BGDB REMOTE ACCESS ==========\n'
printf 'Login user: bgadmin (sudo administrator)\n'
printf 'Codespace name: %s\n' "$cs"
printf 'Container IP (internal only): '
hostname -I 2>/dev/null || printf 'unavailable\n'
printf 'Web editor: https://%s.github.dev\n' "$cs"
printf 'SSH transport: private GitHub CLI tunnel or Tailscale\n'
printf 'Claude Code project: /workspaces/BGDB\n'
if [ -x /home/vscode/.local/bin/claude ]; then
  printf 'Claude Code: installed (vscode profile); run as vscode\n'
elif command -v claude >/dev/null 2>&1; then
  printf 'Claude Code: installed and on PATH\n'
else
  printf 'Claude Code: pending container Rebuild or feature installation\n'
fi
printf 'Claude Code login/start: sudo -iu vscode ; cd /workspaces/BGDB ; claude\n'
if command -v tailscale >/dev/null 2>&1; then
  ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  if [ -n "$ip" ]; then
    printf 'Tailscale IP (private): %s\n' "$ip"
    printf 'iPhone Termius: Host=%s  Port=%s  User=bgadmin  Password=your chosen password\n' "$ip" "$ssh_port"
  else
    printf 'Tailscale not connected yet: run tailscale up and authorize it.\n'
  fi
fi
if [ "$cs" != unknown ]; then
  printf '\nOn the OTHER computer/terminal (once: gh auth login):\n'
  printf '  gh codespace ssh -c %s\n' "$cs"
  printf '\nFor password SSH as bgadmin, run on the OTHER computer:\n'
  printf '  Terminal 1: gh codespace ports forward %s:2222 -c %s\n' "$ssh_port" "$cs"
  printf '  Terminal 2: ssh -p 2222 bgadmin@127.0.0.1\n'
else
  printf 'From the other computer: gh codespace list\n'
fi
printf '\nThe IP above and the github.dev URL are not public SSH hostnames.\n'
printf 'On a fresh/rebuilt container, set the password once: sudo passwd bgadmin\n'
printf '=========================================\n\n'

printf 'BGDB SSH port %s uses SSH host keys, NOT a Lets Encrypt HTTPS certificate.\n' "$ssh_port"
printf 'bgssh.abrdns.com is separate HTTPS ingress (443); it is NOT the SSH port.\n'
