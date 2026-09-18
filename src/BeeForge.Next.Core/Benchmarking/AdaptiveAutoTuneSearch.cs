using System.Text.Json.Nodes;
using LlamaServerLauncher.Optimization.Samplers;
using LlamaServerLauncher.Optimization.Storage;
using LlamaServerLauncher.Optimization.Study;
using LlamaServerLauncher.Optimization.Trial;

namespace BeeForge.Next.Core.Benchmarking;

/// <summary>
/// BeeForge adapter around the unmodified upstream TPE engine. Numeric bounds and
/// stage semantics mirror LlamaServerLauncherAvalonia v1.9.8 OptimizationService.
/// BeeForge keeps its own argv generator and isolated trial process lifecycle.
/// </summary>
public sealed class AdaptiveAutoTuneSearch
{
    private readonly Study _study;
    private readonly AutoTuneCandidate _baseline;
    private readonly int _threadsHigh;
    private readonly int _gpuLayersHigh;
    private readonly int _cpuMoeHigh;
    private readonly bool _tuneCpuMoe;
    private readonly bool _quantizedKv;
    private readonly bool? _fixedFlash;
    private readonly string? _fixedOverride;
    private Trial? _pending;

    public AdaptiveAutoTuneSearch(string profileJson, int seed = 42,
        bool? fixedFlash = null, string? fixedOverride = null)
    {
        var initial = AutoTunePlanner.Candidates(profileJson);
        if (initial.Count == 0) throw new InvalidDataException("Нет допустимых параметров для автоподбора.");
        _baseline = initial[0];
        var profile = JsonNode.Parse(profileJson)!.AsObject();
        _study = Study.Create(new InMemoryStorage(), new TPESampler(seed), StudyDirection.Maximize);
        _threadsHigh = Math.Max(1, Math.Min(Environment.ProcessorCount, 128));
        var modelLayers = Read(profile, "modelLayerCount", 0);
        _gpuLayersHigh = modelLayers > 0
            ? Math.Min(modelLayers, UpstreamBenchmarkDefaults.MaximumGpuLayers)
            : UpstreamBenchmarkDefaults.MaximumGpuLayers;
        var moeLayers = Read(profile, "moeLayerCount", 0);
        _cpuMoeHigh = Math.Min(moeLayers > 0 ? moeLayers : UpstreamBenchmarkDefaults.MaximumCpuMoeLayers,
            UpstreamBenchmarkDefaults.MaximumCpuMoeLayers);
        _tuneCpuMoe = moeLayers > 0 || Read(profile, "cpuMoeLayers", 0) > 0;
        _quantizedKv = new[] { "kvK", "kvV" }.Any(k => profile[k]?.ToString() is { } s &&
            s is not ("f16" or "f32" or "bf16"));
        _fixedFlash = fixedFlash;
        _fixedOverride = fixedOverride;
    }

    public AutoTuneCandidate Ask()
    {
        if (_pending is not null) throw new InvalidOperationException("Предыдущий замер ещё не завершён.");
        _pending = _study.Ask();
        var trial = _pending;
        var batch = trial.SuggestInt("batch", 256, 16384);
        var ubatch = trial.SuggestInt("ubatch", 256, 8192);
        var threads = trial.SuggestInt("threads", 1, _threadsHigh);
        var gpuLayers = trial.SuggestInt("gpu_layers", 0, Math.Max(0, _gpuLayersHigh));
        var cpuMoe = _tuneCpuMoe ? trial.SuggestInt("n_cpu_moe", 0, Math.Max(0, _cpuMoeHigh)) : 0;
        var flash = _fixedFlash ?? (_quantizedKv ? true : _baseline.FlashAttention);
        var tensorOverride = _fixedOverride ?? _baseline.TensorOverride;
        return new AutoTuneCandidate($"TPE {trial.Number + 1}", batch, ubatch, threads,
            threads, flash, gpuLayers.ToString(), _tuneCpuMoe ? cpuMoe : null, tensorOverride);
    }

    public void Tell(AutoTuneTrial result, AutoTuneTrial baseline, OptimizationObjective objective)
    {
        if (_pending is null) throw new InvalidOperationException("Нет активного замера.");
        if (!result.Valid || !baseline.Valid)
            _study.Tell(_pending, null, TrialState.Fail);
        else
        {
            var score = objective switch
            {
                OptimizationObjective.Prefill => result.Prefill,
                OptimizationObjective.Decode => result.Decode,
                _ => (result.Prefill + result.Decode) / 2.0
            };
            _study.Tell(_pending, score);
        }
        _pending = null;
    }

    private static int Read(JsonObject source, string name, int fallback) =>
        source[name] is JsonValue value && value.TryGetValue<int>(out var n) ? n : fallback;
}
