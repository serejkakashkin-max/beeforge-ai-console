---
name: opencode-docker-compose-ops
description: Inspect and operate Docker or Compose through the restricted MCP with confirmation for lifecycle and build actions.
---

# Docker and Compose operations

Begin with status, configuration, and relevant logs. Diagnose from evidence before proposing an action. The MCP is intentionally no-destructive: do not try to bypass its blocks for remove, prune, or kill.

Before start, stop, restart, build, pull, push, or `compose up`, name the project or container and the exact effect, then wait for confirmation. Do not use production or a remote Docker host unless the user names it and confirms the scope.

Use bounded log windows and report before/after state plus any rollback or recovery action.
