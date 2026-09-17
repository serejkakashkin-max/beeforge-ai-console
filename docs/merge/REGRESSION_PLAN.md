# Regression and acceptance plan

Baseline commit: `2446f85` on `main`. Machine-readable status is in `baseline.json`. Failures in this baseline must not be attributed to Avalonia work.

| Gate | Observable evidence | Current status |
| --- | --- | --- |
| Legacy profile roundtrip | Preserve all JSON fields, IDs, unknown extensions and UTF-8 names; backup before write | Fixture read/prepare/idempotency/restore tests pass; live cutover pending |
| Runtime argv parity | Exact ordered argv for BeeLlama/Tiel, KVarN K/V, tail, MoE, MTP, vision, advanced args | `BeeLlamaArgvSnapshot.Smoke.ps1` passes; Next read-only adapter calls the same generator and passes fixture integration; live launch parity pending |
| OpenCode prompts | SHA-256 of each canonical agent prompt; no implicit edits | `PromptSnapshot.Smoke.ps1` added |
| Permissions and routing | Full Access action scope, role-scoped MCP/skills, task allowlist | `Test-BeeFullAccess.ps1`, coordination/policy tests |
| Team Guard | Duplicate/repair/rollover/handoff/history semantics | Node self-test |
| Telegram | Config/DPAPI/allowlist/commands/file/media/clear pin | Node self-tests + ClearPin smoke; live API pending |
| Serena | Existing project registration and memories remain discoverable | Serena tests; live memory smoke pending |
| Remote client | No second Telegram, private Tailscale endpoint, lease | Remote tests; two-PC smoke pending |
| Benchmark | Same run lifecycle and result accounting | Benchmark limits test; actual model run pending |
| Build/installer | Windows x64 packaging and upgrade with state preserved | Distribution passes; RemoteInstall baseline harness fixed and passes in this branch |
| New shell | Starts beside legacy; no profile write on view/open; explicit action parity | Self-contained win-x64 preview; status/start/stop through legacy module with confirmation and lease guard; live launch and visual QA pending |
| Final cutover | Every old feature PASS or explicit BLOCKED in `FINAL_PARITY_REPORT.md` | Not eligible |

Run isolated tests on a copy/fixture, not against live user configuration. `test-mcp.ps1` is a diagnostic command requiring `-McpId`, not a test-suite case. The initial `Test-BeeRemoteInstall.ps1` failure was in its fixture copy: it included restored `node_modules`/`.venv` under a long temporary path. It now copies distributable files only and invokes the installer through `pwsh` as the README does; all original installer assertions remain. Do not trigger live Telegram, a model launch, Tailscale changes, or user profile migration during ordinary unit testing.

At the first Next profile-snapshot milestone: 22 isolated PowerShell tests pass (including the new prompt and argv snapshots), four Node self-tests pass, the .NET profile fixture tests pass, and the Avalonia Release build has no warnings. This is not evidence for live launch, two-device remote operation, or complete UI parity.
