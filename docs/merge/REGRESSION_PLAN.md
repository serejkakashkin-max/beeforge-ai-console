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
| Benchmark | Legacy remains available; Next carries audited upstream benchmark/optimizer behavior | 46 vendored benchmark/optimization/UI source files are locked by SHA-256 aggregate regression; fake HTTP verifies upstream repeat/warmup, PP/TG/TTFT, Prometheus artifact layout and staged search constants; actual-model comparison remains a live gate |
| Build/installer | Windows x64 packaging and upgrade with state preserved | Distribution passes; RemoteInstall baseline harness fixed and passes in this branch |
| New shell | Starts beside legacy; no profile write on view/open; explicit action parity | Release build has 0 warnings; profile CRUD, runtime control, GGUF/HF/VRAM, benchmark/autotune, runtime catalog/install, local on-demand proxy, remote/team controls, logs/help and scenarios are wired through typed adapters. Live launch and visual QA pending |
| Multi-runtime | BeeLlama + upstream llama.cpp + custom executable without silently dropping BeeLlama flags | BeeLlama installer unchanged; upstream Windows CUDA/Vulkan/HIP/SYCL/CPU manager added; arbitrary custom `serverPath` retained; capability probe is per executable. Live upstream launch pending |
| On-demand proxy | Localhost-only model-name/profile router, no provider rewrite | Protocol/profile routing fixtures pass; listener binds `127.0.0.1`, runtime ownership delegates to legacy controller, idle stop supported. Live streaming request pending |
| Final cutover | Every old feature PASS or explicit manual acceptance gate in `FINAL_PARITY_REPORT.md` | Complete: unified self-contained Avalonia launcher is default; legacy launcher retained as explicit fallback |

Run isolated tests on a copy/fixture, not against live user configuration. `test-mcp.ps1` is a diagnostic command requiring `-McpId`, not a test-suite case. The initial `Test-BeeRemoteInstall.ps1` failure was in its fixture copy: it included restored `node_modules`/`.venv` under a long temporary path. It now copies distributable files only and invokes the installer through `pwsh` as the README does; all original installer assertions remain. Do not trigger live Telegram, a model launch, Tailscale changes, or user profile migration during ordinary unit testing.

Current safe regression: 23 isolated PowerShell/smoke tests pass, the .NET compatibility fixture (including upstream runtime selection and on-demand proxy routing) passes, the PowerShell runtime module imports cleanly, and the Avalonia Release build has 0 warnings / 0 errors. These checks intentionally do not claim live model launch, Telegram API delivery, two-device Tailscale operation, existing Serena memories, or visual acceptance.
