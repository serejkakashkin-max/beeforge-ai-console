# Vendored benchmark and optimization source

Source: https://github.com/pytraveler/LlamaServerLauncherAvalonia

Commit: `f52404637d51ec00e15e857d0cd9b33eb9a0b21e` (v1.9.8 source).

`Optimization/**/*.cs` is copied verbatim (line endings may differ). It contains the standalone study, TPE/grid/random samplers, distributions and in-memory storage, without the upstream UI or runtime launcher. MIT license is included and packaged with BeeForge Next. BeeForge's adapter selects bounded runtime parameters and uses the existing BeeLlama argv generator; it does not modify agent prompts, runtime defaults, credentials or production profiles.

The audited v1.9.8 benchmark and optimizer sources are also preserved verbatim under `Benchmarking/`, `OptimizationModels/`, `OptimizationServices/`, `ViewModels/` and `Views/`. SHA-256 equality against upstream is part of the migration verification. These files are the provenance/reference snapshot; BeeForge's compiled adapters retain its profile format, BeeLlama argument generator, exclusive-lease rules and fail-closed temporary-process supervision while reproducing the upstream workload and staged optimizer behavior.

`Services/GgufMetadataService.cs` and `Services/VramEstimator.cs` are also copied verbatim. BeeForge adds bounded preflight and feature-specific caveats outside those files.
