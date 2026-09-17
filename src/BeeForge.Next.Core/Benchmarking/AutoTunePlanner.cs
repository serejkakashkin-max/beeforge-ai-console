using System.Text.Json.Nodes;

namespace BeeForge.Next.Core.Benchmarking;

/// <summary>Small, bounded trial set derived from the upstream staged optimizer idea.
/// Original profiles are never edited while searching.</summary>
public static class AutoTunePlanner
{
    public static IReadOnlyList<AutoTuneCandidate> Candidates(string profileJson)
    {
        var root = JsonNode.Parse(profileJson)?.AsObject() ?? throw new InvalidDataException("Invalid profile.");
        var batch = Read(root, "batch", 2048);
        var ubatch = Read(root, "ubatch", 512);
        var threads = Read(root, "threads", Environment.ProcessorCount);
        var flash = root["flashAttention"]?.GetValue<bool>() ?? true;
        var candidates = new[]
        {
            new AutoTuneCandidate("Исходные", batch, ubatch, threads, flash),
            new AutoTuneCandidate("Крупнее batch", Math.Min(8192, batch * 2), ubatch, threads, flash),
            new AutoTuneCandidate("Крупнее ubatch", batch, Math.Min(batch, Math.Min(2048, ubatch * 2)), threads, flash),
            new AutoTuneCandidate("Меньше потоков", batch, ubatch, Math.Max(1, threads / 2), flash),
            new AutoTuneCandidate("Flash attention", batch, ubatch, threads, !flash),
        };
        return candidates.Where(c => c.Batch is >= 128 and <= 8192 && c.UBatch is >= 64 and <= 8192 &&
            c.UBatch <= c.Batch && c.Threads is >= 1 and <= 128)
            .DistinctBy(c => (c.Batch, c.UBatch, c.Threads, c.FlashAttention)).ToArray();
    }

    public static string CreateTrialProfileJson(string original, AutoTuneCandidate candidate, int port)
    {
        if (port is < 1024 or > 65535) throw new ArgumentOutOfRangeException(nameof(port));
        var root = JsonNode.Parse(original)?.AsObject() ?? throw new InvalidDataException("Invalid profile.");
        root["batch"] = candidate.Batch;
        root["ubatch"] = candidate.UBatch;
        root["threads"] = candidate.Threads;
        root["flashAttention"] = candidate.FlashAttention;
        root["host"] = "127.0.0.1";
        root["port"] = port;
        return root.ToJsonString();
    }

    private static int Read(JsonObject source, string name, int fallback) =>
        source[name] is JsonValue value && value.TryGetValue<int>(out var n) ? n : fallback;
}

public sealed record AutoTuneCandidate(string Name, int Batch, int UBatch, int Threads, bool FlashAttention);
public sealed record AutoTuneTrial(AutoTuneCandidate Candidate, double Prefill, double Decode,
    string? Error)
{
    public bool Valid => Error is null && double.IsFinite(Prefill) && double.IsFinite(Decode) &&
        Prefill > 0 && Decode > 0;
}

public sealed record AutoTuneResult(IReadOnlyList<AutoTuneTrial> Trials, AutoTuneCandidate? Suggested,
    double ImprovementPercent)
{
    public static AutoTuneResult FromTrials(IReadOnlyList<AutoTuneTrial> trials)
    {
        if (trials.Count == 0 || !trials[0].Valid)
            return new AutoTuneResult(trials, null, 0);
        var baseline = trials[0];
        static double RelativeScore(AutoTuneTrial trial, AutoTuneTrial baseline) =>
            0.3 * trial.Prefill / baseline.Prefill + 0.7 * trial.Decode / baseline.Decode;
        var best = trials.Where(t => t.Valid &&
                t.Prefill >= baseline.Prefill * 0.9 && t.Decode >= baseline.Decode * 0.9)
            .OrderByDescending(t => RelativeScore(t, baseline)).First();
        var gain = 100 * (RelativeScore(best, baseline) - 1);
        // Small differences are noise, not a reason to change production settings.
        return gain >= 5 ? new AutoTuneResult(trials, best.Candidate, gain)
            : new AutoTuneResult(trials, null, Math.Max(0, gain));
    }
}
