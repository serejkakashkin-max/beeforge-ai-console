# BeeForge Next migration architecture

## Boundary

Old BeeForge was the running behavior authority during migration. The Avalonia process began as an optional reader/controller through typed compatibility services. After full parity, startup was cut over to the self-contained `BeeForge.Next.App.exe`, and the transitional CMD launchers were removed.

```text
Avalonia Views / ViewModels
       | typed interfaces, no user secrets
BeeForge.Next application services
       | versioned read models + narrowly scoped command adapters
Existing BeeForge PowerShell modules and Node plugins
       | existing profile / OpenCode / Telegram / Serena / Tailscale state
Owned BeeLlama (later pluggable upstream/custom runtimes)
```

## Services and ownership

| Service | First adapter | Single writer / rule |
| --- | --- | --- |
| ProfileCatalog | Read old `profiles.json` as raw JSON without rewriting | Old core remains writer initially; backup before v2 migration |
| InferenceRuntime | Invoke exact existing launch/stop commands with typed ID and bounded timeout | Old PID/current-run files stay authoritative |
| OpenCodeTeam | Read configured agents, invoke existing Save/Restore/FullAccess functions | Preserve prompt bytes, permissions and Team Guard plugin |
| TelegramControl | Existing module status/start/stop | DPAPI token never crosses API, stdout or command line |
| SerenaMemory | Existing project registration/status | Never move/delete `.serena` memories |
| RemoteClient | Existing Tailscale/lease module | No public listener; no client Telegram process |
| Benchmark | Existing benchmark first, versioned result model later | Historical runs remain readable |
| RuntimeCatalog | BeeLlama provider first; upstream/custom adapters later | Feature probes are provider-specific; unsupported flags shown, never silently removed |

No new service may write to `opencode.json` or `profiles.json` concurrently with the legacy module. Profile format migration must be deterministic, reversible and idempotent; the initial shell performs **no migration** and can read legacy profiles. A later migration writes a side-by-side v2 file and validated backup before any switch. Persistent values such as active/last-good IDs remain source-preserved.

## Parity gates

1. Capture current test results and prompt hashes on untouched `main`.
2. Add passive Avalonia shell with status/profile read only; legacy launcher is default.
3. Add equivalent profile/command-line snapshot tests before runtime control.
4. Move each feature behind an adapter with old/new differential tests.
5. Add runtime feature probes, GGUF parsing, planner and optimization as opt-in services.
6. Integrate Team Guard, Telegram, Serena, RemoteClient without replacing their backends.
7. Run live manual and automated parity suite; only then change default launcher. Keep old launcher for at least one release.

## Important conflicts

- LlamaLauncher defaults to upstream llama.cpp; BeeForge needs BeeLlama KVarN/kv-tail/CPU-MoE/MTP/vision. A shared lowest-common-denominator argument builder would regress it.
- LlamaLauncher can launch many instances; BeeForge has an exclusive host/client lease and safe single-model default. Multi-instance stays disabled until ownership and resource accounting are explicit.
- Its llama-server MCP is not OpenCode MCP. Give them separate namespaces and UI pages.
- Its proxy can listen on LAN; BeeForge requires localhost by default and Tailscale-private remote access.
- A .NET UI crash must not kill a server that the legacy launcher/Telegram owns. Future job-object ownership must be explicit and tested.

## Toolchain and deployment

Windows 10/11 x64 first. The baseline host had .NET 8 runtime but no SDK; SDK 8.0.425 was installed for development. The final launcher uses a self-contained win-x64 publish, so the normal application does not depend on a separately installed .NET runtime. No user-specific paths, models, GGUF files, token stores or copied live profiles enter Git.

The Avalonia shell in `src/BeeForge.Next.App/` has progressed beyond the first read-only milestone. It still treats the existing BeeForge modules/files as the behavior authority, but now exposes guarded profile CRUD/import/export, runtime start/stop/connect, GGUF/Hugging Face/VRAM tooling, benchmark/autotune, runtime management, a localhost-only on-demand proxy, scenarios, logs/help, and allowlisted AI-team/remote controls. Opening the UI remains read-only by itself; mutations require explicit actions and preserve backups where applicable.

`ProfileSnapshotMigration` is an opt-in preparation API, not called by the preview UI. It writes a new directory containing an exact legacy-byte backup, normalized JSON snapshot (only absent connection modes gain `LocalHost`), and SHA-256 manifest. It never writes the source file; repeated preparation verifies exact equality and refuses to overwrite a divergent snapshot. Restore creates a copy at a new path after verifying the backup hash. Actual cutover, concurrent-writer ownership, and live-profile migration remain gated by integration tests.

`LegacyLaunchPlanReader` obtains a typed launch plan from `Get-BeeArguments` in the existing BeeForge module. Local BeeLlama flags therefore remain byte/ordering-compatible with the old behavior authority, while RemoteClient produces no local argv. The selected executable is probed separately with `--help`, so upstream/custom runtimes can expose their own capabilities without removing BeeLlama-only flags from BeeLlama profiles.

The unified Avalonia UI uses `LegacyRuntimeController` for status/start/stop. It invokes the existing module through a typed PowerShell entry point; PID ownership, health wait, OpenCode sync and profile save remain authoritative. The entry point additionally rejects local start/stop while a managed remote lease is active and rejects RemoteClient local process actions. UI buttons require explicit confirmation and are disabled until lease status has been read. The Avalonia console is now the default launcher; the legacy PowerShell UI remains a fallback only.

The same typed adapter now exposes `ConnectRemote` for selected RemoteClient profiles. The preview asks for confirmation; the legacy module checks the remote endpoint and alias before writing the active profile or syncing OpenCode. Rejected local-mode and offline-remote attempts are covered by fixture tests asserting that the profile store stays byte-identical. Telegram ownership and the local server process remain unchanged.

The optimization page begins with a bounded, read-only GGUF v2/v3 little-endian metadata and tensor-table reader based on ggml's [format specification](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md) and [tensor type enum](https://github.com/ggml-org/ggml/blob/master/include/ggml.h). It skips tokenizer arrays and tensor payloads, exposes only small architecture/configuration fields plus counts by tensor type, and rejects malformed counts, duplicate names and truncation. The current local GGUF was inspected successfully (866 tensor descriptors, no payload read). Big-endian files and future structural versions are reported as unsupported; VRAM estimates are deliberately not inferred from a few metadata fields. The reader never writes to a model or profile.

The dashboard displays memory and uptime from the existing status command, not from a second process monitor. The system page reads at most the last 64 KiB of an explicit allowlist of old runtime/Telegram log files, without changing them. That is observation only; Telegram, Team Guard and OpenCode remain owned by the old services.

The AI Workspace page reads a whitelist of OpenCode agent IDs, modes, model IDs, disabled states and MCP IDs/enabled states. It never returns agent prompts, MCP commands/URLs, keys or permissions. A live read of the existing configuration found nine agents and eight MCP servers without changing its file hash. Management remains in the legacy console until mutation/backup parity is demonstrated.

## Current multi-runtime and proxy boundary

BeeLlama remains the default managed runtime and keeps its verified installer. `UpstreamLlamaRuntimeManager` installs official `ggml-org/llama.cpp` Windows builds into a separate version/backend tree for CUDA, Vulkan, HIP, SYCL or CPU, verifies GitHub-provided SHA-256 digests when available, stages extraction, keeps a rollback copy and never changes an active profile. A profile can also point at an arbitrary custom `llama-server.exe`; feature probing is executable-specific.

`LocalOnDemandProxy` is optional and binds strictly to `127.0.0.1`. The OpenAI `model` field maps to a local profile alias/name/ID, runtime lifecycle is delegated to the existing BeeForge controller, and an idle timeout may unload the model that the proxy loaded. It does not rewrite OpenCode, does not open LAN/Tailscale listeners and does not bypass the existing remote lease policy.

Automatic multi-instance fan-out is intentionally not adopted. The original BeeForge safety contract uses one heavy-model owner and an exclusive remote lease; profile scenarios and the runtime catalog provide management structure without violating that contract. A future concurrent-runtime mode would require a separate ownership/resource-accounting design and is not a prerequisite for the current single-model product.
