# BGDB SSH Manager — Tera Term-inspired ChatGPT MCP connector

Status: DESIGN ONLY — not deployed; no live SSH or Claude Code connection is implied.
Owner: BGDB INFO (ykinfohome7). Keep existing SSL/TLS scanner and HVD repository unchanged.

## Source and licensing
- Tera Term 5 upstream: https://github.com/TeraTermProject/teraterm
- Official project: https://teratermproject.github.io/index-en
- Tera Term and TTSSH are BSD 3-clause licensed; review each reused module's individual notices and transitive dependencies.
- The Tera Term GUI and TTSSH DLL depend on Windows / Win32. **Do not port the whole GUI or run Windows DLLs on Linux.**
- Reproduce the relevant SSH *behavior* with maintained Linux OpenSSH client infrastructure instead. Do not copy code unless required and licenses are preserved.

## Target architecture
ChatGPT ↔ authenticated MCP server ↔ policy/approval + audit layer ↔ Linux OpenSSH client ↔ explicitly authorized SSH hosts.
Private SSH key material resides only in the server-side secret store or dedicated SSH agent, never in repo, prompts, tool output, or logs.
Known hosts are pinned and checked strictly (no automatic blind host-key acceptance).

## Feature roadmap
Phase 1, read-only proof of concept:
- list configured host aliases, connection test, execute an allowlisted read-only command (uname, uptime, id) and return structured stdout/stderr/exit code.
- UTF-8 including Bulgarian/Russian text; command timeout, maximum output size, explicit target.
- No public port-22 exposure required if deployed in a network that can reach the host securely.

Phase 2, controlled administration:
- keyed authentication, multiple independent simultaneous SSH sessions; session ids; session close; precise per-host authorization.
- file transfers (SFTP); command presets; audit records; explicit approval for commands that change state.
- no arbitrary shell execution, privilege escalation or root login by default.

Phase 3, optional visual terminal:
- browser terminal UI with tabbed sessions, Unicode/Cyrillic, configurable font/size, xterm.js or equivalent.
- Browser UI is independent of the headless MCP interface. No Windows GUI port needed.

## Security and deployment requirements
- Run with a non-root service account; container isolation, per-host user and network allowlist, rate limits.
- Block shell injection: fixed command presets; never interpolate untrusted text into a shell command string.
- SSH host-key checking enabled; no StrictHostKeyChecking=no.
- Store secrets in an access-controlled secret manager (or agent), not GitHub files, workflow output, or conversation.
- Require a user confirmation for writes/restarts/firewall changes; all changes logged with actor/target/status.
- Return only sanitized outputs. Keep SSH port private via VPN, zero-trust tunnel or bastion; no blanket internet exposure.
- Each test explicitly distinguishes simulated success, local process success, and actual remote connection success.

## Claude Code implementation task
1. Create a standalone Python MCP SSH server in this directory using maintained MCP Python tooling and OpenSSH for transport, plus a mock transport for tests.
2. Implement list_hosts, connection_check and run_safe_command with explicit host + preset command selection.
3. Write unit tests for host policy, host-key rejection, timeouts, UTF-8 output, secret redaction, session errors, and subprocess injection resistance.
4. Add CI tests which **never** require real user SSH keys or remote hosts; no automatic deployment.
5. Document separate interactive setup steps for the owner, including server-side secrets injection and approved-host enrollment.
6. Return a pull request for review before merge. Do not touch scanner scripts or HVD.

## Completion criteria
- CI passes in INFO and the read-only test prints exit status and the sanitized output.
- No private keys in repository; no unaudited command execution.
- Live SSH access is tested only after owner separately connects an approved host.
- Claude Code is NOT running automatically merely because this document exists.
