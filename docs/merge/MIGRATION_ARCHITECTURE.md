# BeeForge Next migration architecture

## Boundary

Old BeeForge is the running behavior authority. The Avalonia process is initially an optional reader/controller through typed compatibility services, not a second independent config writer or replacement daemon. The old WPF launcher and `BEEFORGE-AI.cmd` stay intact until full parity.

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

Windows 10/11 x64 first. The baseline host had .NET 8 runtime but no SDK; SDK 8.0.425 was installed for the preview build, without changing the legacy launcher. Existing users keep the PowerShell launcher until the new build and migration pass. No user-specific paths, models, GGUF files, token stores or copied live profiles enter Git.

The first Avalonia shell is now a read-only preview in `src/BeeForge.Next.App/`. Its separate core adapter reads the legacy profile store, defaults missing `connectionMode` to `LocalHost`, and preserves original JSON in memory without writing anything. It deliberately does **not** start or stop a model, edit OpenCode, migrate user state, or replace the WPF launcher. This is an implementation milestone, not cutover or parity.

`ProfileSnapshotMigration` is an opt-in preparation API, not called by the preview UI. It writes a new directory containing an exact legacy-byte backup, normalized JSON snapshot (only absent connection modes gain `LocalHost`), and SHA-256 manifest. It never writes the source file; repeated preparation verifies exact equality and refuses to overwrite a divergent snapshot. Restore creates a copy at a new path after verifying the backup hash. Actual cutover, concurrent-writer ownership, and live-profile migration remain gated by integration tests.

`LegacyLaunchPlanReader` obtains a typed, read-only launch plan from `Get-BeeArguments` in the existing BeeForge module. The adapter sends only a fixture/profile-store path and profile ID to a bounded PowerShell process; it does not start a server or interpolate user input into a command string. Local BeeLlama flags are therefore generated by the old behavior authority, while RemoteClient produces no local argv. Independent upstream/custom runtime controllers, their capability probes and process-ownership parity remain future gates.

The optional preview now has a separate `LegacyRuntimeController` for status/start/stop. It invokes the existing module through a typed PowerShell entry point; the old PID ownership, health wait, OpenCode sync and profile save remain authoritative. The new entry point additionally rejects local start/stop while a managed remote lease is active and rejects RemoteClient local process actions. UI buttons require an explicit modal confirmation and are disabled until lease status has been read. This is not yet process/health parity for an upstream or custom runtime, and it does not switch the default launcher.

The same typed adapter now exposes `ConnectRemote` for selected RemoteClient profiles. The preview asks for confirmation; the legacy module checks the remote endpoint and alias before writing the active profile or syncing OpenCode. Rejected local-mode and offline-remote attempts are covered by fixture tests asserting that the profile store stays byte-identical. Telegram ownership and the local server process remain unchanged.

The optimization page begins with a bounded, read-only GGUF v2/v3 little-endian metadata and tensor-table reader based on ggml's [format specification](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md) and [tensor type enum](https://github.com/ggml-org/ggml/blob/master/include/ggml.h). It skips tokenizer arrays and tensor payloads, exposes only small architecture/configuration fields plus counts by tensor type, and rejects malformed counts, duplicate names and truncation. The current local GGUF was inspected successfully (866 tensor descriptors, no payload read). Big-endian files and future structural versions are reported as unsupported; VRAM estimates are deliberately not inferred from a few metadata fields. The reader never writes to a model or profile.

The dashboard displays memory and uptime from the existing status command, not from a second process monitor. The system page reads at most the last 64 KiB of an explicit allowlist of old runtime/Telegram log files, without changing them. That is observation only; Telegram, Team Guard and OpenCode remain owned by the old services.
