---
name: opencode-safe-operations
description: Operate the local Windows PC or an SSH host with explicit scope, reversible actions, and confirmation gates; use for system and remote operations.
---

# Safe operations

Inspect state first and report the exact target before changing it. Use native Windows UI or PowerShell for local operations. For SSH, use aliases or keys from `~/.ssh/config`, `BatchMode=yes`, and preserve host-key checking.

Ask before deletion, overwrite, service stop/restart, network changes, credential changes, or sending data outside the PC. Never request, store, print, or disable protection for passwords, keys, tokens, or host verification.

Use bounded commands and timeouts. Report the action, target, outcome, and a recovery step when one exists.
