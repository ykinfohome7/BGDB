#!/usr/bin/env bash
# Display Codespaces identity and supported external SSH connection command.
cs="${CODESPACE_NAME:-unknown}"
printf '\n======== BGDB CONNECTION INFO ========\n'
printf 'User: bgadmin (sudo admin)\n'
printf 'Codespace: %s\n' "$cs"
printf 'Internal container IP(s): '
hostname -I 2>/dev/null || printf 'unavailable\n'
printf 'Web IDE: https://%s.github.dev\n' "$cs"
if [ "$cs" != unknown ]; then
  printf 'SSH from another terminal: gh codespace ssh -c %s\n' "$cs"
else
  printf 'SSH from another terminal: gh codespace list (then gh codespace ssh -c NAME)\n'
fi
printf 'Note: internal IP and github.dev web address are NOT direct SSH endpoints.\n'
printf '======================================\n\n'
