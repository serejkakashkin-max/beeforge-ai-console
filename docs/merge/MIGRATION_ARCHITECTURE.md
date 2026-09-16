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

Windows 10/11 x64 first. The host currently has .NET 8 runtime but no SDK; build verification requires installing a pinned .NET 8 SDK or a CI Windows runner. Existing users keep the PowerShell launcher until the new build and migration pass. No user-specific paths, models, GGUF files, token stores or copied live profiles enter Git.
