---
name: opencode-safe-operations
description: Operate the local Windows PC or an SSH host with explicit scope, reversible actions, and confirmation gates; use for system and remote operations.
---

# Safe operations

Inspect state first and report the exact target before changing it. Use native Windows UI or PowerShell for local operations. For SSH, prefer Python Paramiko first; check that it is available in the selected Python environment. Resolve aliases from `~/.ssh/config` explicitly (Paramiko does not apply that file automatically), preserve the configured user, port and identity, load known host keys and reject unknown or changed keys. Use connection, authentication and command timeouts; close clients and channels. Do not use AutoAddPolicy or silently trust a host key. Use existing keys or an SSH agent without printing credentials. If Paramiko is unavailable or incompatible with a required SSH feature, explain the reason and fall back to native ssh.exe/scp.exe/sftp.exe with BatchMode=yes and host-key checking. Do not introduce WSL or install packages merely to perform SSH.

Ask before deletion, overwrite, service stop/restart, network changes, credential changes, or sending data outside the PC. Never request, store, print, or disable protection for passwords, keys, tokens, or host verification.

Use bounded commands and timeouts. Report the action, target, outcome, and a recovery step when one exists.
