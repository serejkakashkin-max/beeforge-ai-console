using System.Text.Json.Nodes;
using LlamaServerLauncher.Optimization.Samplers;
using LlamaServerLauncher.Optimization.Storage;
using LlamaServerLauncher.Optimization.Study;
using LlamaServerLauncher.Optimization.Trial;

namespace BeeForge.Next.Core.Benchmarking;

/// <summary>BeeForge parameter adapter around the unmodified upstream TPE engine.</summary>
public sealed class AdaptiveAutoTuneSearch
{
    private readonly Study _study;
    private readonly AutoTuneCandidate _baseline;
    private readonly int[] _batches, _ubatches, _threads, _batchThreads;
    private readonly bool[] _flash;
    private readonly string[] _gpuLayers;
    private readonly int[] _moe;
    private Trial? _pending;

    public AdaptiveAutoTuneSearch(string profileJson, int seed = 42)
    {
        var initial = AutoTunePlanner.Candidates(profileJson);
        if (initial.Count == 0) throw new InvalidDataException("Нет допустимых параметров для автоподбора.");
        _baseline = initial[0];
        var profile = JsonNode.Parse(profileJson)!.AsObject();
        _study = Study.Create(new InMemoryStorage(), new TPESampler(seed, nStartupTrials: 4), StudyDirection.Maximize);
        _batches = Choices(_baseline.Batch, 128, 8192);
        _ubatches = Choices(_baseline.UBatch, 64, Math.Min(2048, _batches.Max()));
        _threads = Choices(_baseline.Threads, 1, Math.Min(128, Environment.ProcessorCount));
        _batchThreads = Choices(_baseline.ThreadsBatch, 1, Math.Min(128, Environment.ProcessorCount));
        // Quantized KV may require FA. Never disable it speculatively for those profiles.
        var quantized = new[] { "kvK", "kvV" }.Any(k => profile[k]?.ToString() is { } s && s is not ("f16" or "f32" or "bf16"));
        _flash = quantized ? new[] { _baseline.FlashAttention } : new[] { false, true };
        _gpuLayers = initial.Select(c => c.GpuLayers ?? profile["gpuLayers"]?.ToString() ?? "all").Distinct().ToArray();
        _moe = initial.Select(c => c.CpuMoeLayers ?? profile["cpuMoeLayers"]?.GetValue<int>() ?? 0).Distinct().ToArray();
    }

    public AutoTuneCandidate Ask()
    {
        if (_pending is not null) throw new InvalidOperationException("Предыдущий замер ещё не завершён.");
        _pending = _study.Ask();
        var trial = _pending;
        return new AutoTuneCandidate($"TPE {trial.Number + 1}",
            trial.SuggestCategorical("batch", _batches), trial.SuggestCategorical("ubatch", _ubatches),
            trial.SuggestCategorical("threads", _threads), trial.SuggestCategorical("threadsBatch", _batchThreads),
            trial.SuggestCategorical("flash", _flash), trial.SuggestCategorical("gpuLayers", _gpuLayers),
            trial.SuggestCategorical("cpuMoeLayers", _moe));
    }

    public void Tell(AutoTuneTrial result, AutoTuneTrial baseline, OptimizationObjective objective)
    {
        if (_pending is null) throw new InvalidOperationException("Нет активного замера.");
        if (!result.Valid || !baseline.Valid)
            _study.Tell(_pending, null, TrialState.Fail);
        else
        {
            var pp = result.Prefill / baseline.Prefill;
            var tg = result.Decode / baseline.Decode;
            var score = objective switch { OptimizationObjective.Prefill => pp, OptimizationObjective.Decode => tg, _ => 0.3 * pp + 0.7 * tg };
            _study.Tell(_pending, score);
        }
        _pending = null;
    }

    private static int[] Choices(int basis, int minimum, int maximum) =>
        new[] { Math.Clamp(basis / 2, minimum, maximum), Math.Clamp(basis, minimum, maximum),
            (int)Math.Clamp((long)basis * 2, minimum, maximum) }.Distinct().Order().ToArray();
}
