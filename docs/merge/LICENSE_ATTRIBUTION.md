# Source and license attribution

`LlamaServerLauncherAvalonia` by pytraveler is licensed under MIT, copyright © 2026 pytraveler. Audited upstream commit: `f52404637d51ec00e15e857d0cd9b33eb9a0b21e`. Full original license: [upstream LICENSE](https://github.com/pytraveler/LlamaServerLauncherAvalonia/blob/main/LICENSE).

The BeeForge Next architecture, UI and benchmarking code are original implementations informed by upstream behavior; **no upstream source file has been copied**. The repeatable `/completion` workload and staged baseline/candidate/confirmation design were informed by `Services/Optimization/HttpBenchmarkService.cs` and `OptimizationService.cs` at the audited commit. If a future change adapts a substantial upstream implementation, include the MIT copyright and permission notice in the distribution, annotate the adapted file with its upstream path/commit, and record the adaptation here. Track additional dependencies and their licenses separately before packaging.

BeeForge's existing code, prompts, plugins and private user state retain their own provenance. Neither project’s live configuration, secrets nor model weights are part of source attribution or a distributable source tree.
