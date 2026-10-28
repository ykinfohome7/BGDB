# BGDB Codespace – automatic recovery on start

The BGDB Codespace is the **SSH target** for the separate
[`ykinfohome7/ssh-connector`](https://github.com/ykinfohome7/ssh-connector)
BGSSH GitHub Actions service. The target's SSH transport is on **port 2222**,
via private Tailscale (not an exposed public SSH endpoint).

## Every start/resume
The devcontainer `postStartCommand` runs
`.devcontainer/restore-on-start.sh`. It:
1. Starts/repairs OpenSSH and checks that `sshd` listens on **2222**.
2. Reuses the original SSH server host keys from the per-Codespace volume.
   Logs only the **public host-key fingerprint**, never a private key.
3. Starts/checks Tailscale, restoring its state from its per-Codespace volume
   where supported. A new Codespace may need manual Tailscale authorization.
4. Restores the Claude Code and Codex CLI binaries and links; their config
   directories are also persistent volumes. If Node.js is unavailable, rebuild
   to apply the Node LTS devcontainer feature.
5. Prints warnings rather than silently changing remote DNS/certificates.

Persistent mount targets: `/var/lib/bgdb-ssh-hostkeys`, `/var/lib/tailscale`,
`/home/vscode/.claude`, `/home/vscode/.codex`, and
`/home/vscode/.local/share/bgdb-ai-tools`.

## After a rebuild
The devcontainer changes (new mounts and Node feature) require one **Rebuild
Container**. The same Codespace normally retains its named volumes, but
**deleting and recreating the Codespace is not a backup**: its data, Tailscale
identity, host keys, and local credentials may be lost. Keep independent backups
of indispensable data in a private trusted store.

SSH logins: `bgadmin` with the password or keys you configured, using
**private Tailscale IP:2222**. Existing passwords are not stored in the Git
repository, restored from plaintext, or automatically recreated on a fresh
container; if an account password is missing after rebuilding, run
`.devcontainer/finish-bgdb-setup.sh` in the interactive terminal. For higher
security, move to key-based SSH and disable root password SSH logins once
you have verified `bgadmin` access.

To check a started container:

```bash
sudo /usr/sbin/sshd -T | grep -E '^(port|passwordauthentication|permitrootlogin) '
sudo ss -ltn | grep ':2222'
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
tailscale ip -4
bash /workspaces/BGDB/.devcontainer/show-connection.sh
claude --version
codex --version
```

If the **Tailscale IPv4 changes**, update the `BGDB-Codespaces` target in
`ykinfohome7/ssh-connector/config/github-session.yaml` (or its private
`SSH_CONNECTOR_SERVERS` override). If the **SSH host fingerprint changes**
(e.g. entirely new Codespace), independently verify it and update the
`SSH_CONNECTOR_KNOWN_HOSTS` GitHub Actions secret. Never turn off host-key
checking to make the connection pass.

## SSL certificate and ClouDNS are separate
The user has a Let's Encrypt certificate for `bgssh.abrdns.com` and
`*.bgssh.abrdns.com` (2026-10-28–2027-01-25), managed in ClouDNS.
This is a **TLS certificate for the public HTTPS ingress**, **not** the
Codespace's SSH identity on port 2222. Neither certificate nor private key
is uploaded or downloaded by this boot script. Public A-record DDNS must run
only from a real stable HTTPS ingress, **not from a temporary Codespace or
GitHub Actions runner**; see the separate connector repository's
`docs/cloudns-ddns.md`.

Current HTTPS ingress for `bgssh.abrdns.com` must be configured and tested
separately. Do not claim its DNS/TLS endpoint is up merely because SSH works.

## Offline verification
```bash
bash -n .devcontainer/restore-on-start.sh
python3 tests/test_codespace_restore.py
```
