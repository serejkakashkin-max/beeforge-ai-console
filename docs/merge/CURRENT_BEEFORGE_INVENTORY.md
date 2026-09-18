# BeeForge current behavior inventory

Baseline: `main` commit `2446f85` (16 September 2026). This is the behavior contract for BeeForge Next. Files under `config/`, `runtime/`, `logs/`, `backups/`, `benchmarks/`, `secrets/`, and user OpenCode/Serena directories are user state, not migration source files. Never overwrite them from a template.

| Function | Implementation | State / files changed | Processes / external dependencies | Existing evidence |
| --- | --- | --- | --- | --- |
| Windows launcher and current UI | `local/BeeForge.Next/BeeForge.Next.App.exe`, desktop shortcut, `ui/BeeLlama-Manager.ps1` (legacy maintenance UI only) | Reads profile store, writes through core modules | .NET 8 self-contained Avalonia | `Test-Distribution.ps1`, `Test-BeeRemoteUi.ps1` |
| Profile schema and defaults | `BeeLlamaManager.Core.psm1`: `Initialize-BeeProfileSchema`, `Get-BeeProfileStore`, `Get-BeeNewProfileTemplate` | `config/profiles.json`; active and last-good IDs; model roots | None | `RuntimeProfile.Smoke.ps1`, `Test-BeeRemoteProfiles.ps1` |
| Profile save and migration | `Save-BeeProfileStore`, `Initialize-BeeProfileSchema` | Atomic-ish temp replacement of profile store; legacy defaults and CPU-MoE flags | File system | `RuntimeProfile.Smoke.ps1`, `MoEProfile.Smoke.ps1` |
| Model/projector discovery and validation | `Get-BeeModelFiles`, `Get-BeeVisionProjectorFiles`, `Test-BeeProfile`, `Test-BeeVisionProfile` | Reads GGUF, MMProj and runtime paths | `llama-server.exe --help` | `BeeLlamaRuntime.Smoke.ps1`, `RuntimeProfile.Smoke.ps1` |
| BeeLlama launch arguments | `Get-BeeArguments`, `Get-BeeCommandPreview`, `Test-BeeProfile` | All profile runtime fields, advanced flags | BeeLlama or custom `llama-server.exe` | `RuntimeProfile.Smoke.ps1`, `MoEProfile.Smoke.ps1`, new command snapshot |
| BeeLlama-only options | `Get-BeeArguments` | Separate K/V KVarN, KV tail, CPU MoE, tensor override, MTP, reasoning, no-mmap, vision | BeeLlama feature probe | `MoEProfile.Smoke.ps1`, `BeeLlamaRuntime.Smoke.ps1`, new command snapshot |
| Runtime lifecycle and ownership | `Start-BeeServer`, `Stop-BeeServer`, `Get-BeeServerStatus`, `server-manager.ps1` | `logs/qwen38-server.pid`, `logs/current-run.json`, stdout/stderr | Owned `llama-server.exe`, localhost health | `Test-BeeExclusiveLease.ps1`; live smoke pending |
| Remote model client | `Connect-BeeRemoteProfile`, `Test-BeeRemoteConnection`, `BeeForgeRemote.Core.psm1` | Remote profile fields, `config/remote-access.json` | HTTPS Tailscale Serve | Remote Access/Profiles/UI tests |
| Exclusive host/client lease | `Test-BeeLocalModelLeased`, remote core | Remote-access state | Prevents concurrent local/remote use | `Test-BeeExclusiveLease.ps1` |
| OpenCode provider sync | `Update-BeeOpenCode` | User `opencode.json`, backup in `backups/` | OpenCode | `Test-BeePolicySync.ps1`, `Test-BeeRemoteProfiles.ps1` |
| AI team and editor | `BeeForgeTeam.Core.psm1`, `ui/BeeLlama-Manager.ps1` | User `opencode.json`, skill/MCP assignments, backups | OpenCode MCPs and skills | Team Coordination/MCP/Skill tests |
| Prompts and routing | `opencode/opencode.template.json`, `opencode/AGENTS.md`, `Sync-BeeAgentPrompts.ps1` | User `opencode.json` | OpenCode agents | Prompt SHA-256 snapshot, Team Coordination test |
| Full Access | `Set-BeeFullAccess`, `Get-BeeFullAccessStatus` | `runtime/access/full-access.json`, user `opencode.json`, audit log | OpenCode permission engine | `Test-BeeFullAccess.ps1` |
| Team Guard | `tools/team-guard/v1.0.0/plugin.mjs`, template plugin | Session/handoff guard state and OpenCode history | OpenCode plugin API | `self-test.mjs` |
| Skills and MCP | `Sync-BeeSkills.ps1`, `BeeForgeTeam.Core.psm1`, `opencode/skills/` | User skills folder and OpenCode config | Serena, GitHub, Playwright, etc. | Skill, MCP catalog, policy tests |
| Serena project memory | `BeeForgeSerenaMemory.Core.psm1`, `tools/serena/v1.7.0/` | Per-project `.serena` and global Serena registration | Serena MCP | Serena Memory/Lazy/Repair tests |
| Telegram configuration and DPAPI token | `BeeForgeTelegram.Core.psm1` | `config/telegram.json`, `secrets/`, scheduled task | Windows DPAPI, Telegram API | Telegram bridge self-tests; live E2E pending |
| Telegram bridge commands, queue, status pin, file/media/voice | `tools/telegram-bridge/v1.0.0/bridge.mjs`, `voice-service.py` | Telegram state/logs, project inbox, pinned message | Node, Telegram, faster-whisper | Bridge/Clear self-tests and ClearPin smoke |
| Telegram lifecycle | `Run-BeeTelegramBridge.ps1`, `BeeForgeTelegram.Core.psm1` | PID, log, token store | Node process, Telegram long polling | Bridge self-test; live E2E pending |
| Benchmark limits and runs | `Start-BeeBenchmark`, `Resolve-BeeBenchmarkRequest`, `scripts/run-benchmark.ps1` | `benchmarks/`, `logs/benchmark-test.*` | BeeLlama HTTP endpoint | `Test-BeeBenchmarkLimits.ps1` |
| Runtime and dependency installation | `Install-BeeForge.ps1`, `Install-BeeLlamaRuntime.ps1` | `runtime/`, config templates, user integrations | GitHub releases, OpenCode, Node, Python | Distribution, remote install test (known path failure) |
| Tailscale Serve | `BeeForgeRemote.Core.psm1` | `config/remote-access.json`, Tailscale Serve config | Tailscale CLI | `Test-BeeRemoteAccess.ps1` |
| Safety and retention | Core modules, `.gitignore`, `Test-Distribution.ps1` | Backups, logs, protected secrets | File system | Distribution and policy tests |

The inventory is a migration checklist, not a claim that every live end-to-end path has been exercised. Telegram live API, actual model startup, Serena against the user's existing memories, and Tailscale across two PCs require controlled integration checks before cutover. Existing profile values and prompts are not to be rewritten during the UI migration.
