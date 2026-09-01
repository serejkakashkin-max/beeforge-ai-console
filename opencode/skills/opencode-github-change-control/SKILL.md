---
name: opencode-github-change-control
description: Use GitHub MCP for repository work with clear scope and confirmation before any remote mutation; use for Issues, PRs, Actions, releases, and repository metadata.
---

# GitHub change control

Read repository state, target, and existing discussion before proposing a mutation. For create, edit, close, merge, push, release, permission, or deletion actions, state the repository and exact remote effect, then wait for confirmation.

Never expose secrets, tokens, private variables, or Actions credentials. After a mutation, return the resulting URL or identifier and a concise outcome. Do not treat local repository edits as authorization to change GitHub.
