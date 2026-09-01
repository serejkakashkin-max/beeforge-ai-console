---
name: opencode-quality-engineering
description: Design and execute risk-based unit, integration, regression, and browser testing with reproducible evidence; use for QA, test planning, verification, and code review, not feature implementation.
---

# Quality engineering

Start from the requested behavior, developer handoff, and highest-risk regression. Inspect only the relevant test stack and reuse its conventions before adding tools or dependencies.

- Define observable acceptance criteria and the smallest useful test matrix.
- Prefer integration tests for user-facing behavior; use unit tests for isolated logic and edge cases.
- Reproduce a reported defect before proposing a fix when practical.
- Use deterministic data, bounded waits, and stable semantic selectors. Do not hide flaky behavior with retries or arbitrary sleeps.
- Run the narrowest relevant checks first, then broaden only when risk justifies it.
- Do not repeat successful checks recorded in the handoff unless the working state changed.
- `FAST` is the default; use `STANDARD` or `RELEASE` only when the Team Lead passes that mode.
- Record the command, environment, expected result, actual result, and any skipped coverage.

Do not modify production code unless the user explicitly requests a fix. Test files and fixtures may be changed when test authoring is requested. For browser flows, use the assigned browser MCP and never submit irreversible forms or alter external accounts without confirmation.

Finish with pass/fail status, evidence, residual risk, a concise recommendation, and a handoff stating what must not be repeated.
