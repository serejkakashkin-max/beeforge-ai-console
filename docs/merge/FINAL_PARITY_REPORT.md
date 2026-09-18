# BeeForge AI Console Next — final parity report

This report compares the behavior contract captured from BeeForge `main` at baseline commit `2446f85` with the current BeeForge Next implementation. `PASS` means the implementation exists and has automated/isolation evidence. `BLOCKED` is reserved for acceptance that requires a live user model, real Telegram API, existing Serena project memory, a second Tailscale device, or visual/manual interaction. `NOT ADOPTED` means a reference feature conflicts with an explicit BeeForge product rule and is intentionally excluded.

| Feature | Old BeeForge | New BeeForge | Status | Evidence / test |
| --- | --- | --- | --- | --- |
| Existing profile compatibility | Reads/writes `config/profiles.json` | Reads the same store, missing `connectionMode` defaults to `LocalHost`, unknown fields retained | PASS | .NET compatibility fixture; profile backup/stale-write tests |
| Active/last-good profile | Preserved in profile store | Preserved through reads/edits/migration preparation | PASS | .NET profile fixture |
| Profile CRUD/import/export | WPF/PowerShell UI | Avalonia profile manager with backups and validation | PASS | .NET fixture + Release build |
| Profile migration | Existing format is production source | Compatibility layer opens existing profiles directly; optional deterministic/reversible snapshot migration available | PASS | snapshot idempotency/restore fixture |
| BeeLlama runtime | Managed BeeLlama v0.4.6 installer | Preserved unchanged and exposed in Next runtime manager | PASS | `BeeLlamaRuntime.Smoke.ps1`, distribution checks |
| BeeLlama KVarN K/V | BeeLlama-specific flags | Exact existing argument generator remains authority | PASS | `BeeLlamaArgvSnapshot.Smoke.ps1`, `RuntimeProfile.Smoke.ps1` |
| KV tail | Existing BeeLlama profile fields | Preserved in legacy argv and Next profile editor | PASS | argv snapshot + profile fixture |
| CPU MoE | `--n-cpu-moe` / `--cpu-moe` | Preserved and autotune-aware | PASS | `MoEProfile.Smoke.ps1`, .NET autotune fixture |
| Tensor override | `-ot`/`--override-tensor` | Preserved | PASS | `RuntimeProfile.Smoke.ps1`, argv snapshot |
| MTP/speculative parameters | Existing BeeLlama flags | Preserved in argv and profile editor | PASS | argv snapshot + .NET launch-plan fixture |
| Reasoning settings | Existing profile fields | Preserved by profile model/editor and legacy generator | PASS | profile roundtrip/unknown-field preservation |
| Flash Attention/batch/ubatch/threads/context/GPU layers | Existing profile fields | Preserved and exposed in Next; optimizer can vary bounded safe candidates | PASS | runtime profile smoke + .NET optimizer fixtures |
| Vision/MMProj | Existing projector fields and checks | File picker, profile fields, launch parity retained | PASS | argv snapshot + projector compatibility smoke |
| Custom advanced args | Existing JSON list | Preserved and editable | PASS | profile roundtrip + launch plan fixture |
| Upstream llama.cpp runtime | Manual custom executable only | Managed official ggml-org releases for Windows CUDA/Vulkan/HIP/SYCL/CPU; separate version/backend paths and rollback | PASS | .NET selector fixture + zero-warning build; live upstream launch is a separate gate |
| Custom llama-server runtime | `serverPath` can point at runtime | Still supported; per-executable `--help` capability probe | PASS | runtime capability fixtures |
| Runtime version management | BeeLlama-specific | BeeLlama catalog plus independent upstream version/backend tree and prior-build rollback | PASS | runtime catalog/unit fixtures |
| Runtime capability detection | BeeLlama validation | Exact selected executable probed; unsupported flags reported rather than silently removed | PASS | .NET capability fixtures |
| Server start/stop/status | Legacy module owns PID/health | Next delegates through typed adapter to same module | PASS | isolated controller fixtures; live model acceptance BLOCKED below |
| Crash diagnostics | Logs/manual inspection | Bounded advisor for OOM/CUDA/port/unsupported/model-load failures | PASS | .NET crash advisor fixture |
| Orphan-process safety | Legacy ownership/PID checks | Persistent server still owned by legacy backend; optimizer child process uses fail-closed Windows job | PASS | Windows job fixture + legacy ownership tests |
| GGUF metadata | Not available | Bounded v2/v3 metadata reader | PASS | .NET synthetic GGUF fixture |
| GGUF tensor table/splits | Not available | Tensor table reader/type summary and split validation | PASS | .NET GGUF fixture |
| Model/MMProj pickers | Basic file selection | Native Avalonia file pickers | PASS | Release build + code path |
| Hugging Face search | Not available | Search + repository GGUF listing | PASS | URL/input fixtures; live HF API is external availability |
| Hugging Face resume | Not available | `.part` range-resume download | PASS | service implementation + Release build |
| Gated HF token | Not available | Reads only local HF environment token; never placed in CLI/UI/log | PASS | implementation boundary + distribution secret checks |
| VRAM estimator | Basic legacy resource estimate | Detailed weights/KV/compute/projector plan with dense/MoE/hybrid support; BeeLlama-special values marked advisory when exact fit cannot be proven | PASS | dense/MoE/hybrid/KVarN .NET fixtures |
| VRAM actual comparison | Live status | Next compares reliable estimate with live observed VRAM | PASS | status/view-model path; live numerical acceptance BLOCKED below |
| Hardware monitor | Legacy subset | CPU/GPU/RAM/VRAM/temp/context/uptime/tokens/slots | PASS | adapter/status fixtures + module tests |
| Live PP/TG/slots | Legacy benchmark/status | Current PP/TG and bounded slots snapshot surfaced | PASS | typed runtime adapter + build |
| Benchmark workload | Existing benchmark | Audited upstream `/completion` request and repeat/warmup semantics, PP/TG/TTFT and Prometheus snapshot | PASS | exact-source SHA-256 verification + fake HTTP fixture + `Test-BeeBenchmarkLimits.ps1` |
| Benchmark history | Retained legacy files | Upstream-style per-run artifact directory (`run.json`, `report.md`, optional `metrics.prom`) plus compatibility reader for earlier Next history | PASS | .NET persistence fixture |
| Benchmark comparison/export | Limited | Multi-run PP/TG/TTFT comparison and Markdown export | PASS | .NET comparison fixture |
| Automatic optimizer | Not present | Upstream Stage 1 TPE → Stage 2 Flash/Tensor Override grid → Stage 3 TPE → 256/128 × 6 comparison, with BeeForge isolated-process/profile safety | PASS | exact-source snapshot + .NET TPE/defaults/grid/profile-backup fixtures |
| Optimizer objective | Not present | PP, TG, balanced | PASS | .NET objective fixture |
| Optimizer safety | Not present | Isolated port/process, minimum gain threshold, backup, source profile remains unchanged | PASS | .NET fixtures + Windows job fixture |
| Scenarios/presets | Profiles only | Ordered scenarios, atomic store/backups, manual first-profile selection | PASS | .NET scenario fixture |
| Automatic heavy multi-instance | Single heavy model / exclusive lease | Intentionally remains single-heavy-model by default; no automatic fan-out | NOT ADOPTED | Product rule: preserve `parallel=1`/exclusive owner safety |
| On-demand OpenAI proxy | Direct provider only | Optional localhost-only router, model alias/name/ID → profile, idle unload | PASS | protocol/routing fixtures + loopback-only listener code; live streaming acceptance BLOCKED below |
| Offline contextual help | Tutorial/README | Allowlisted bundled help topics | PASS | .NET help fixture |
| OpenCode Team Lead/specialists | Existing team | Existing OpenCode backend preserved; Next reads safe inventory only | PASS | `Test-BeeTeamCoordinationPolicy.ps1`, MCP/skill policy tests |
| Specialist prompts | Existing prompts | Not rewritten by migration | PASS | `PromptSnapshot.Smoke.ps1` |
| Role permissions | Existing permissions/Full Access | Existing backend retained and Next calls allowlisted Full Access actions | PASS | `Test-BeeFullAccess.ps1`, policy tests |
| Skills | Role-scoped skills | Preserved | PASS | `Test-BeeSkillSync.ps1` |
| OpenCode MCP | Role-scoped MCP | Preserved and shown separately from llama-server MCP | PASS | `Test-BeeTeamMcpCatalog.ps1` |
| llama-server MCP | Not previously exposed | Separate per-profile option, off by default, only emitted when configured/supported | PASS | .NET launch-plan fixture |
| Team Guard | Delegation/repair/handoff/rollover | Backend unchanged | PASS | coordination policy + existing Node self-tests |
| Full Access semantics | Action permission expansion only | Preserved; does not grant unrelated MCP/skill catalog access | PASS | `Test-BeeFullAccess.ps1`, policy tests |
| Serena activation/memory | Existing MCP/project memory | Backend preserved, lazy memory/project rules retained; Next can show summaries | PASS | Serena memory/lazy/config-repair tests |
| Telegram config/DPAPI/allowlist | Existing bridge | Backend unchanged | PASS | distribution + bridge self-tests |
| Telegram commands/tasks/files/media | Existing bridge | Backend unchanged | PASS | bridge self-tests and policy baseline; real Telegram E2E BLOCKED below |
| Telegram clear/pin | Existing behavior | Preserved/fixed | PASS | `TelegramBridge.ClearPin.Smoke.ps1` |
| RemoteClient | Local project/tools + remote inference | Preserved | PASS | remote profile/install/UI/access tests |
| Tailscale private-only access | Tailscale Serve, no public port | Preserved | PASS | `Test-BeeRemoteAccess.ps1`, `Test-BeeExclusiveLease.ps1` |
| Exclusive remote lease | Local/remote mutually exclusive | Preserved and enforced by Next adapter | PASS | `Test-BeeExclusiveLease.ps1` + .NET lease fixture |
| RemoteClient no Telegram bridge | Required | Preserved by installer | PASS | `Test-BeeRemoteInstall.ps1` |
| Secrets hygiene | DPAPI/no tracked state | Next does not surface prompt/MCP secrets, HF token or runtime secrets | PASS | `Test-Distribution.ps1`, OpenCode snapshot fixture |
| Windows x64 packaging | Existing scripts | Avalonia Release build/publish alongside legacy fallback | PASS | Release build, distribution checks |
| Default launcher cutover | Legacy launcher was the previous default | Desktop shortcut now targets the self-contained `BeeForge.Next.App.exe` directly; CMD launchers were removed | PASS | Direct EXE launch smoke verified |

## Safe regression evidence

The current branch passed all safe automated checks without starting the user's production model or mutating live Telegram/Tailscale/Serena state:

- 23 PowerShell/smoke regression scripts: PASS.
- `BeeForge.Next.Core.Tests` compatibility/integration fixture: PASS (`NEXT_PROFILE_READONLY_TEST_OK`).
- Avalonia `Release` build: 0 warnings, 0 errors.
- PowerShell runtime module import: PASS.
- Distribution/no-user-state checks: PASS.

## Remaining live/manual acceptance gates

These are not implementation TODOs. They require controlled interaction with the user's real environment and therefore remain final acceptance checks after the user-authorized cutover:

| Gate | Status | Remaining acceptance evidence |
| --- | --- | --- |
| Existing BeeLlama/Tiel profile live start | BLOCKED | Start the real model from Next and compare generated argv/health/startup with legacy |
| Same-profile speed | BLOCKED | Compare PP/TG/startup on identical model/runtime/settings; no material regression |
| Upstream llama.cpp live start | BLOCKED | Install one official build, select it in a copied profile and confirm health/stop/rollback |
| On-demand proxy streaming | BLOCKED | Send a real OpenAI-compatible streaming request through `127.0.0.1:18080` and confirm profile load/idle unload |
| Telegram live API | BLOCKED | Real bot command/file/image/final-answer/clear-dialog roundtrip |
| Existing Serena memories | BLOCKED | Open a real existing project and verify activation/read/update without losing memory |
| Two-PC RemoteClient | BLOCKED | Main PC + notebook Tailscale smoke with exclusive lease and local project tools |
| Visual/UI acceptance | BLOCKED | User validates scaling, profile editing, confirmations, logs, optimization and runtime manager on the production desktop |

The user explicitly authorized the final cutover before completing all manual environment gates. The unified Avalonia console is now launched directly through `BeeForge.Next.App.exe`; the desktop shortcut points to that executable and uses the BeeForge icon. CMD launchers are no longer part of the normal or fallback startup path.
