# Regression and acceptance plan

Baseline commit: `2446f85` on `main`. Machine-readable status is in `baseline.json`. Failures in this baseline must not be attributed to Avalonia work.

| Gate | Observable evidence | Current status |
| --- | --- | --- |
| Legacy profile roundtrip | Preserve all JSON fields, IDs, unknown extensions and UTF-8 names; backup before write | Existing smoke partial; add fixture differential test |
| Runtime argv parity | Exact ordered argv for BeeLlama/Tiel, KVarN K/V, tail, MoE, MTP, vision, advanced args | Existing smoke partial; add snapshot before runtime cutover |
| OpenCode prompts | SHA-256 of each canonical agent prompt; no implicit edits | `PromptSnapshot.Smoke.ps1` added |
| Permissions and routing | Full Access action scope, role-scoped MCP/skills, task allowlist | `Test-BeeFullAccess.ps1`, coordination/policy tests |
| Team Guard | Duplicate/repair/rollover/handoff/history semantics | Node self-test |
| Telegram | Config/DPAPI/allowlist/commands/file/media/clear pin | Node self-tests + ClearPin smoke; live API pending |
| Serena | Existing project registration and memories remain discoverable | Serena tests; live memory smoke pending |
| Remote client | No second Telegram, private Tailscale endpoint, lease | Remote tests; two-PC smoke pending |
| Benchmark | Same run lifecycle and result accounting | Benchmark limits test; actual model run pending |
| Build/installer | Windows x64 packaging and upgrade with state preserved | Distribution test; RemoteInstall known long-path failure |
| New shell | Starts beside legacy; no write on view/open | Not yet implemented |
| Final cutover | Every old feature PASS or explicit BLOCKED in `FINAL_PARITY_REPORT.md` | Not eligible |

Run isolated tests on a copy/fixture, not against live user configuration. `test-mcp.ps1` is a diagnostic command requiring `-McpId`, not a test-suite case. `Test-BeeRemoteInstall.ps1` copies bundled `node_modules` into a long temporary path and currently fails on Windows path length before assertions; fix it separately without weakening the installer assertions. Do not trigger live Telegram, a model launch, Tailscale changes, or user profile migration during ordinary unit testing.
