---
name: opencode-safe-operations
description: Operate the local Windows PC or an SSH host with explicit scope, reversible actions, and confirmation gates; use for system and remote operations.
---

# Safe operations

Inspect state first and report the exact target before changing it. Use native Windows UI, PowerShell, cmd, or Windows Python for local operations. WSL is forbidden for agent operations: never invoke `wsl.exe`, `wsl -d`, Linux shells through WSL, `sshpass`, or WSL/ASKPASS fallbacks. For SSH key authentication, use native Windows `ssh.exe`/`scp.exe`/`sftp.exe`, aliases or keys from `~/.ssh/config`, `BatchMode=yes`, and preserve host-key checking. If the user explicitly authorizes password authentication and has already supplied the credential in the current task/project input, use native Windows Python + Paramiko without exposing it in output, command lines, environment variables, or temporary files.

Ask before deletion, overwrite, service stop/restart, network changes, credential changes, or sending data outside the PC. Never request, persist a new copy of, print, or disable protection for passwords, keys, tokens, or host verification.

Use bounded commands and timeouts. Report the action, target, outcome, and a recovery step when one exists.
