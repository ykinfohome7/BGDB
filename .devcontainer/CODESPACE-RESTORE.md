# BGDB Codespace — restore on startup

## What happens when you resume the BGDB Codespace
`.devcontainer/devcontainer.json` runs `.devcontainer/restore-codespace.sh`
through `postStartCommand` on each startup, without prompting in the background.

- Restore/start OpenSSH on **private port 2222** with the existing BGDB
  `bgadmin`/root login policy. Do not forward 2222 publicly.
- Save and restore the Codespace **SSH server host key pair** securely in
  `/workspaces/.bgdb-private/ssh-host-keys` (outside the Git repository);
  on an ordinary stop/start and rebuild with preserved workspace storage the
  verified server identity remains stable.
- Start or detect Tailscale. If authorization was lost, use the existing
  interactive `.devcontainer/finish-bgdb-setup.sh` in a terminal to reconnect.
- Reinstall missing Claude Code / OpenAI Codex CLI tools (without unnecessarily
  re-installing when already present); authentication may still be required.
- Restore BGSSH MCP from `ykinfohome7/ssh-connector` to
  `~/.local/share/bgdb-ssh-connector`, retain existing configuration, and
  register the local `bgssh` MCP for Claude Code and Codex.
- Create a key for local vscode -> bgadmin@127.0.0.1:2222, install that public
  key into `/home/bgadmin/.ssh/authorized_keys`, and pin the SSH server's
  *locally read* public host key in a separate `known_hosts` file.
- Verify real local SSH authentication on port 2222, not merely that `sshd`
  is installed.

## Security / certificate separation

- **SSH port 2222 uses SSH host keys**, NOT the Let's Encrypt HTTPS
  certificate.
- The existing Let's Encrypt certificate (RSA 2048, domain
  `bgssh.abrdns.com`, wildcard `*.bgssh.abrdns.com`, valid Oct 28
  2026–Jan 25 2027) applies to HTTPS termination at an ingress on **443**.
  It has not been installed in this Codespace by this change.
- No certificate private key, token, password, DDNS DynamicURL or Tailscale
  auth key is committed to either repository.
- GitHub Actions still exposes a **temporary** MCP HTTP backend using its own
  HTTPS URL. Resuming a Codespace does NOT create an inbound public port 443
  or make `bgssh.abrdns.com` point to that runner.
- The separate GitHub Actions session has to run and pass its real HTTPS
  probe before an external ChatGPT/Claude connector can use it.
- SSH host keys survive only while the Codespace's persistent workspace
  storage exists. Deleting/recreating the Codespace loses these keys;
  re-verify `SSH_CONNECTOR_KNOWN_HOSTS` in GitHub Actions in that case.
- Passwords from `/etc/shadow` may not survive a Codespace **rebuild**
  (unlike stop/start); `finish-bgdb-setup.sh` prompts for setting them.
  User account logins and OAuth for Claude/Codex may also need reauthorization.
- `/workspaces/.bgdb-private` is outside the `BGDB` repository; it is
  a root-only state directory and must never be synced into public Git.

## Current connection after restoring

```text
BGDB Codespace:
  user: bgadmin
  SSH: port 2222
  Tailscale IP: print using tailscale ip -4 (not hard-coded)
  Claude Code workspace: /workspaces/BGDB
  Local MCP: bgssh, SSH target 127.0.0.1:2222
HTTPS (separate service):
  hostname: bgssh.abrdns.com
  public port: 443
  certificate: Let's Encrypt, installed on the eventual HTTPS ingress only
```

## Check / repair manually

```bash
bash /workspaces/BGDB/.devcontainer/restore-codespace.sh
cat ~/.cache/bgdb/codespace-restore.log
sudo /usr/sbin/sshd -T | grep '^port '
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
tailscale ip -4
claude mcp list
codex mcp list
bash /workspaces/BGDB/.devcontainer/show-connection.sh
```

If a Codespace is rebuilt from GitHub, its `postStartCommand` will also
run, but some steps require network/approval/login. Do not claim that a
successful bootstrap alone verifies public domain HTTPS reachability.

## Local CI for the bootstrap

```bash
bash -n .devcontainer/restore-codespace.sh
bash -n .devcontainer/setup-bgadmin.sh
bash -n .devcontainer/restore-bgssh-mcp.sh
python3 -m json.tool .devcontainer/devcontainer.json >/dev/null
```
