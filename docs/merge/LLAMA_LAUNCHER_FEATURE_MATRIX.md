# LlamaServerLauncherAvalonia feature matrix

Reference: `pytraveler/LlamaServerLauncherAvalonia` commit `f52404637d51ec00e15e857d0cd9b33eb9a0b21e`, release-source version 1.9.8. This repository is a design/reference input, not a replacement for BeeForge. “Planned” does not mean implemented.

| Capability | Reference implementation | BeeForge today | BeeForge Next adoption / constraint |
| --- | --- | --- | --- |
| Avalonia shell, themes, MVVM | `App.axaml`, `MainWindow.axaml`, `ViewModels/` | WPF/PowerShell | Read-only preview installed alongside legacy; full parity pending |
| Profiles and import/export | `ConfigurationService`, `ProfileInfo`, `MainViewModel` | BeeForge `profiles.json`, import/export UI | Legacy profiles listed with active selection and read-only command plan; editor/import/export pending |
| GGUF metadata/tensors/splits | `GgufMetadataService`, `ModelScanService` | Basic model-file picker | Planned after isolated parser tests |
| VRAM prediction and actual comparison | `VramEstimator`, `VramPlan`, `VramComparison` | Live VRAM monitoring | Planned; extend to KVarN, MoE, hybrid attention and BeeLlama logs |
| Model/MMProj pickers | `ModelPickerViewModel`, picker windows | Local pickers | Planned; preserve current paths |
| HuggingFace search/resumable download | `HuggingFaceClient`, `HfDownloadService` | Not present | Planned; token must never be CLI/logged |
| Runtime build download/rollback | `LlamaCppDownloadService`, `BackendAssetSelector` | BeeLlama installer | Planned separate providers: BeeLlama, upstream llama.cpp, custom |
| Runtime flag detection | `LlamaHelpParserService`, `NativeRuntimeProbe` | BeeLlama `--help` validation | BeeLlama still uses legacy validation/argv; multi-runtime capability union pending |
| Hardware CPU/GPU/RAM/VRAM/temperature | `HardwareMonitorService` | Runtime stats subset | Planned; avoid polling during model load |
| Multi-instance | `LlamaServerService`, `ServerInstance` | Single model, exclusive remote lease | Infrastructure only at first; default remains one heavy model |
| Live PP/TG/slots | `InferenceStatsParser`, server service | Benchmark/status stats | Planned integrated dashboard |
| Benchmark history/comparison | `BenchmarkStorageService`, comparison VM | Run/status and retained files | Next preview: `/completion` workload, discarded warmup, repeated PP/TG mean and spread, per-profile private JSON history with profile fingerprint; richer reports/filtering pending |
| Auto optimizer | `OptimizationService`, samplers/pruners | Not present | Next preview: isolated baseline and bounded batch/ubatch/threads/flash trial set, confirmation, minimum 5% improvement, optional backed-up copy of profile; upstream TPE/pruners and VRAM-aware search pending |
| On-demand OpenAI proxy | `OnDemandProxyService` | Direct OpenCode provider | Planned opt-in, localhost default; no provider disruption |
| Scenarios/presets | Scenario model/dialog | Profiles | Planned opt-in, no automatic heavy-model fanout |
| Crash advisor/process job | `ServerCrashAdvisor`, `WindowsProcessJob` | PID/ownership checks | Planned only after parity on process ownership |
| Contextual offline help | `HelpService`, bundled docs | Tutorial/README | Planned in new shell |
| llama-server MCP | `McpConfigService` | OpenCode MCP only | Planned as **separate** inference integration, disabled by default |
| Telegram, Team Guard, Serena, Tailscale | Not provided by reference | Core BeeForge features | Preserve BeeForge services unchanged |

Reference feature list: [upstream README](https://github.com/pytraveler/LlamaServerLauncherAvalonia). Before adapting source, inspect the specific file's provenance and retain the MIT notice described in `LICENSE_ATTRIBUTION.md`.
