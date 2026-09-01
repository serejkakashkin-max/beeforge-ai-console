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

## Lazy maintenance

Memory maintenance belongs to the specialist who already owns the requested task; it is not a mandatory preliminary stage.

- Missing or incomplete memories never block the requested task and never justify a separate Solution Architect delegation by themselves.
- For ordinary implementation, Software Engineer starts the requested work immediately, reads relevant existing memories, and records only durable facts actually verified during that work.
- Do not scan unrelated repository areas merely to create all five files or reach `5/5`. Partial memory is valid and grows across useful tasks.
- Use Solution Architect for broad onboarding only when the user explicitly requests onboarding/project mapping or architecture/research is itself the requested work.
- Before HANDOFF, the responsible specialist updates relevant memories when new stable facts were learned. If nothing durable changed or was learned, do not rewrite memory.

## Verification contract

Every required memory that is created or materially updated must contain this machine-checkable block:

```markdown
## Verification
- Last verified: YYYY-MM-DD
- Scope: concise description of what was actually checked
- Evidence: `relative/path`, `symbol`, or verified command
- Unknown: known gaps, or `none`
```

Treat memory as a cache, not as the source of truth. If current source, configuration, or verified runtime behavior conflicts with memory, the current evidence wins: correct the memory and mention the reconciliation in HANDOFF. Keep branch-specific and temporary facts out unless the memory clearly labels their scope.

Role boundaries prevent unnecessary delegations while limiting memory pollution:

- Software Engineer may update all five required memories, but only within facts learned during implementation.
- Solution Architect may update all five during explicit onboarding, architecture, or research work.
- Quality Engineer may update only test-related parts of `suggested_commands` and `task_completion`.
- DevOps Engineer and Platform Engineer may update only infrastructure-related parts of `tech_stack`, `suggested_commands`, and `task_completion`.
- Systems Engineer and Security Engineer provide memory candidates in HANDOFF; they do not write project memory unless the user explicitly expands their scope.

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
4. Update memories after a task reveals new durable facts, after a verified architectural change, an explicit memory-maintenance request, or a RELEASE handoff. Do not rewrite unchanged memories.
5. Software Engineer, Solution Architect, Quality Engineer, DevOps Engineer, and Platform Engineer may write/edit memories only within the role boundaries above. Solution Architect and Quality Engineer remain strictly read-only for project source. Memory rename is limited to Software Engineer and Solution Architect. Memory deletion is critical and requires confirmation.
6. Run `serena memories check` after onboarding or a substantial memory update and report missing or stale topics.
7. End every HANDOFF with exactly one memory result: `Memory: updated <names> — <reason>` or `Memory: unchanged — no new durable facts`.
