---
name: opencode-serena-memory
description: Maintains durable Serena project memories for every opened or explicitly activated project without special-casing project locations.
---

# Serena project memory

Use this skill only for durable, verified project knowledge. Never use memories as a session log.

## Project scope

- The same durable-memory rules apply to every project, regardless of location, Git remote, whether it appears in the OpenCode sidebar, or whether the user supplied its path only for the current request.
- When the user gives an exact project path, activate that exact path before reading its config. Initialize memory when it is missing, then read `memory_maintenance` before onboarding or updates.
- Do not confuse memory persistence with source-write authorization. A read-only diagnostic request still forbids source changes, while verified durable project facts may be maintained in Serena memory.

## Required durable memories

Onboarding creates and maintains these focused memories:

- `core`: purpose, boundaries, entry points, high-level module map.
- `tech_stack`: languages, frameworks, runtimes, package/build systems.
- `suggested_commands`: verified local commands for build, test, lint and run.
- `conventions`: stable coding and repository conventions.
- `task_completion`: verified completion checks and release expectations.

## Rules

1. Read `memory_maintenance` first and follow it.
2. Store only stable, non-obvious, verified facts useful in later sessions. Reference files or symbols where practical.
3. Never store secrets, credentials, tokens, personal data, full tool output, temporary status, speculative conclusions, or a chronology of the current task.
4. Update memories only after a verified architectural change, an explicit memory-maintenance request, or a RELEASE handoff. Do not rewrite unchanged memories.
5. Solution Architect may write/edit/rename memories for every activated project while remaining strictly read-only for source code. Memory deletion is critical and requires confirmation.
6. Run `serena memories check` after onboarding or a substantial memory update and report missing or stale topics.
