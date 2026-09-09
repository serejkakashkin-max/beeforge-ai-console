# Model/runtime tuning notes

BeeForge profiles distinguish settings that affect the **llama-server runtime** from metadata advertised to **OpenCode**.

## CPU threads

- `Threads decode` maps to `-t/--threads` and mainly affects decode plus operations left on CPU.
- `Threads prefill` maps to `-tb/--threads-batch` and mainly affects prompt processing/prefill.
- More logical threads are not automatically faster. Benchmark both values on the target CPU.

## OpenCode output

`Output (OpenCode)` is written to `provider.beellama.models.<alias>.limit.output`. It is **not** a VRAM setting and is not passed to llama-server. For reasoning models BeeForge uses `32768` as the default so long reasoning turns are not cramped without advertising an unnecessarily huge 65K response.

The server-side `Reasoning budget` is a separate setting.

## Vision projector safety

When the main GGUF changes, BeeForge only auto-selects a projector located in the **same model directory**. It no longer silently carries a projector from the previous model. Obvious cross-family combinations such as Ornith + Qwen3.8 mmproj are rejected before launch. Projectors stored elsewhere can still be selected manually; unknown family matches produce a warning.

## MoE on limited VRAM

`CPU MoE layers` / `--n-cpu-moe` is primarily a **capacity fallback**. It can make a large GGUF load, but substantial routed-expert offload can make decode RAM/CPU-bound. Do not assume a 20 GB Q4 MoE will stay fast on a 16 GB GPU just because it starts successfully.

Preferred order for a daily driver:

1. choose the largest quant that nearly fits in VRAM at the context you actually need;
2. keep `GPU layers = all` where possible;
3. benchmark short context (16–32K) first to establish decode potential;
4. increase context after speed is confirmed;
5. use `CPU MoE` only when the quality benefit is worth the speed loss;
6. when a model author publishes a tested tensor-level recipe, use `Tensor override` (`-ot`) instead of broad offload and A/B-test it.

`--no-mmap` is exposed as an opt-in switch for CPU-heavy offload experiments. It is not a universal speed switch and requires enough physical RAM.

## Runtime-state correctness

BeeForge stores a SHA-256 fingerprint of the effective llama-server argument list for each launch. Saving a profile after changing batch, KV, MTP, threads, MoE or other runtime settings no longer makes the UI assume that the already-running server matches the edited profile.

## Resource estimator

The resource tab is intentionally conservative. Hybrid/linear-attention models can use materially less classic KV cache than the Qwen3.8 calibration. Fine-grained tensor overrides cannot be inferred from GGUF size, so the estimator marks their split as unknown and prefers actual dedicated VRAM/RAM after a real launch.
