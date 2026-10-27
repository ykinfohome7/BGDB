#!/usr/bin/env bash
# Show Codespaces identity and safe private SSH connection commands.
cs="${CODESPACE_NAME:-unknown}"
printf '\n========== BGDB REMOTE ACCESS ==========\n'
printf 'Login user: bgadmin (sudo administrator)\n'
printf 'Codespace name: %s\n' "$cs"
printf 'Container IP (internal only): '
hostname -I 2>/dev/null || printf 'unavailable\n'
printf 'Web editor: https://%s.github.dev\n' "$cs"
printf 'SSH transport: authenticated GitHub CLI (not direct public TCP)\n'
if [ "$cs" != unknown ]; then
  printf '\nOn the OTHER computer/terminal (once: gh auth login):\n'
  printf '  gh codespace ssh -c %s\n' "$cs"
  printf '\nFor password SSH as bgadmin, run on the OTHER computer:\n'
  printf '  Terminal 1: gh codespace ports forward 22:2222 -c %s\n' "$cs"
  printf '  Terminal 2: ssh -p 2222 bgadmin@127.0.0.1\n'
else
  printf 'From the other computer: gh codespace list\n'
fi
printf '\nThe IP above and the github.dev URL are not public SSH hostnames.\n'
printf 'On a fresh/rebuilt container, set the password once: sudo passwd bgadmin\n'
printf '=========================================\n\n'
