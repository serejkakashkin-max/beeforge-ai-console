# Vendored optimization engine

Source: https://github.com/pytraveler/LlamaServerLauncherAvalonia

Commit: `f52404637d51ec00e15e857d0cd9b33eb9a0b21e` (v1.9.8 source).

`Optimization/**/*.cs` is copied verbatim (line endings may differ). It contains the standalone study, TPE/grid/random samplers, distributions and in-memory storage, without the upstream UI or runtime launcher. MIT license is included and packaged with BeeForge Next. BeeForge's adapter selects bounded runtime parameters and uses the existing BeeLlama argv generator; it does not modify agent prompts, runtime defaults, credentials or production profiles.
