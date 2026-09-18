# Source and license attribution

`LlamaServerLauncherAvalonia` by pytraveler is licensed under MIT, copyright © 2026 pytraveler. Audited upstream commit: `f52404637d51ec00e15e857d0cd9b33eb9a0b21e`. Full original license: [upstream LICENSE](https://github.com/pytraveler/LlamaServerLauncherAvalonia/blob/main/LICENSE).

The standalone upstream `Optimization/**/*.cs` engine (study, TPE/grid/random samplers, distributions and storage) is vendored without semantic changes in `third_party/LlamaServerLauncher/Optimization`. Its complete MIT notice is in `third_party/LlamaServerLauncher/LICENSE` and is copied to `licenses/LlamaServerLauncher-MIT.txt` in the application distribution. `AdaptiveAutoTuneSearch` is BeeForge's adapter to that engine. Runtime argv, profile persistence, lease restrictions and confirmation remain BeeForge-owned.

The audited benchmark/optimizer source is preserved byte-for-byte under `third_party/LlamaServerLauncher/Benchmarking`, `OptimizationModels`, `OptimizationServices`, `ViewModels` and `Views`. BeeForge Next uses its own integration UI/runtime adapters, but the standard `/completion` request shape, repeat/warmup semantics, PP/TG/TTFT collection, Prometheus snapshot, upstream defaults, three-stage TPE → grid → TPE optimizer, tensor-override grid and final comparison workload are now reproduced from that source. BeeForge-specific safety remains outside the vendored code: production profiles are never edited during search, temporary servers remain isolated, and exclusive remote leases are respected.

BeeForge's existing code, prompts, plugins and private user state retain their own provenance. Neither project’s live configuration, secrets nor model weights are part of source attribution or a distributable source tree.

`src/BeeForge.Next.Core/Inference/WindowsProcessJob.cs` adapts upstream `Services/WindowsProcessJob.cs` at the same commit: SafeHandle ownership and fail-closed errors replace optional logging. Only temporary optimization servers are attached; persistent BeeForge runtime lifecycle is unchanged.

`third_party/LlamaServerLauncher/Services/GgufMetadataService.cs` and `VramEstimator.cs` are copied from the same upstream commit. The BeeForge `VramPlanner` wrapper performs bounded GGUF preflight, maps existing profiles, and marks unsupported BeeLlama cache/tail/MTP/override layouts as requiring actual runtime measurement. It does not use an approximate result to automatically alter profiles.
