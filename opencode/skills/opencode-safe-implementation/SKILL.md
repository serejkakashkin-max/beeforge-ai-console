---
name: opencode-safe-implementation
description: Implement a bounded change in the current repository with evidence and focused verification; use for coding tasks, not external operations.
---

# Safe implementation

An assignment explicitly marked `PLAN_ONLY`, `READ_ONLY`, or `NO CHANGES` is not authorization to implement. In that mode, inspect only, do not create or modify files, do not run mutating commands, and return findings or a proposed plan to the requesting agent.

Before editing, identify the relevant files, existing tests, and pre-existing working-tree changes. Keep the requested scope narrow and preserve unrelated edits.

Make the smallest coherent change. Run the most relevant available checks with a finite timeout. If a check cannot run, state the exact reason rather than claiming success.

Do not push, create releases, alter remote services, or handle secrets. Summarize changed files, verification evidence, and remaining limitations.
