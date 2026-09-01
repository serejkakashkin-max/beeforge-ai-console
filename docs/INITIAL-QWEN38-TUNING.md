# Archived Qwen3.8 / BeeLlama tuning report

> Historical measurements from 2026-08-26. Current profiles are managed in
> **BeeForge AI Console**; this document is retained only as a tuning reference.

Runtime: BeeLlama v0.4.3 (commit `ba27edad2`), Windows CUDA 13.1 companion runtime.
Model: `%USERPROFILE%\.lmstudio\models\zerodigest\Qwen3.8-27B-Uncensored-YMQ-MTP-GGUF\Qwen3.8-27B-Uncensored-YMQ-S-Pro.gguf` (11.697 GiB, qwen35, 27.32B, IQ3_XXS 3.0625 bpw, native context 262144, NextN/MTP tensors present).

## Deployed experimental profile

| Setting | Value |
|---|---|
| Context | 180000 |
| GPU layers | all |
| KV K / V | KVarN4 / KVarN4 |
| KV precision tail | 1024 F16 |
| Batch / ubatch | 2048 / 512 |
| Threads / batch threads | 16 / 16 |
| Flash Attention / parallel | on / 1 |
| MTP | off: measured fastest; native MTP 2/3/4 reduced throughput |
| Reasoning | on, medium via OpenCode template kwargs, unrestricted (`--reasoning-budget -1`) |
| Preserve thinking / loop guard | on / force-close |
| Sampling | temperature 1.0; top_p .95; top_k 20; min_p 0; repeat penalty 1.0 |
| API | `http://127.0.0.1:8080/v1` |

180K configured for real-world validation; full 150–160K synthetic fill was intentionally not required before deployment. Reasoning is intentionally configured as unrestricted with reasoning_effort=medium. No 4096-token hard reasoning cap is enabled. CPU inference threads are configured to 16.

The observed 180K baseline was ~15.7–15.9 GiB VRAM after load and ~15.9 GiB during a controlled 23,594-token prefill; no OOM observed, but headroom is narrow. This is not mathematically proven production-stable.

## Performance tuning (2026-08-26)

The server retains physical context 180000 (internally aligned to 180224). OpenCode advertises the same physical limit, but uses `limit.input=48000` and `compaction.reserved=16000`, so compaction starts at roughly 32000 input tokens. This avoids the severe attention slowdown observed once an agent session had grown to roughly 38K–50K tokens.

| Test | Result |
|---|---:|
| 8K prefill, batch 512 / ubatch 256 | 1400.92 tok/s |
| 8K prefill, batch 2048 / ubatch 512 | 1778.95 tok/s |
| 8K prefill, ubatch 1024 (`llama-bench`) | 1852.90 tok/s, but poor real-server behavior; rejected |
| 17.1K real-server prefill, context 64K | 1648.37 tok/s |
| 17.1K real-server prefill, context 180K | 1687.59 tok/s |
| KV KVarN4/KVarN4 | 1778.95 tok/s |
| KV KVarN4/KVarN3 | 1771.67 tok/s |
| KV KVarN3/KVarN3 | 1786.30 tok/s |

KV differences were below 1%, so KVarN4/KVarN4 was retained for quality. Physical context size did not materially affect clean prefill speed. The major slowdown in the real OpenCode log came from adding new tokens at an already large KV depth; prompt-prefix caching was working, but attention cost still rises with depth.

| MTP | Wall | Decode | Acceptance | Mean accepted length | VRAM after |
|---|---:|---:|---:|---:|---:|
| OFF | 6.99 s | 37.64 tok/s | — | — | 15808 MiB |
| n-max 2 | 18.30 s | 14.99 tok/s | 68.06% | 2.36 | 15867 MiB |
| n-max 3 | 14.65 s | 18.99 tok/s | 67.19% | 3.00 | 15900 MiB |
| n-max 4 | 14.99 s | 18.65 tok/s | 55.38% | 3.22 | 15846 MiB |

MTP is intentionally OFF because every tested native MTP setting was substantially slower than ordinary decode on this model/runtime/GPU combination.

## Current launch method

1. Run `C:\AI\BeeForge AI Console\BEEFORGE-AI.cmd` or the desktop shortcut.
2. Select a profile and click **Сохранить и запустить** or **Применить и перезапустить**.
3. Open OpenCode; its config is `%USERPROFILE%\.config\opencode\opencode.json`.
4. Stop the managed server with **Остановить** in BeeForge AI Console.

If the server fails, inspect `C:\AI\BeeForge AI Console\logs`. OpenCode backups are
stored in `C:\AI\BeeForge AI Console\backups`; the manager retains the 10 newest
automatic copies for up to 30 days.
