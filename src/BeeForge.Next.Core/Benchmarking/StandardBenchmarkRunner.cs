using System.Security.Cryptography;
using System.Text;
using System.Diagnostics;

namespace BeeForge.Next.Core.Benchmarking;

public sealed class StandardBenchmarkRunner
{
    private readonly HttpBenchmarkProbe _probe;
    private readonly BenchmarkRunStore _store;

    public StandardBenchmarkRunner(HttpBenchmarkProbe probe, BenchmarkRunStore store)
    {
        _probe = probe;
        _store = store;
    }

    public async Task<StoredBenchmarkRun> RunAsync(BenchmarkRunRequest request,
        IProgress<BenchmarkProgress>? progress, CancellationToken cancellationToken)
    {
        request.Validate();
        var endpoint = new Uri(request.ApiBaseUrl, UriKind.Absolute);
        await _probe.VerifyModelAsync(endpoint, request.ModelAlias, cancellationToken);
        var watch = Stopwatch.StartNew();
        var samples = new List<BenchmarkSample>(Math.Max(1, request.Repeats - 1));
        for (var i = 0; i < request.Repeats; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var warmup = request.Repeats > 1 && i == 0;
            progress?.Report(new BenchmarkProgress(i + 1, request.Repeats,
                warmup ? "Разогрев" : "Измерение"));
            var sample = await _probe.MeasureAsync(endpoint, request.ModelAlias, request.PromptTokens,
                request.OutputTokens, TimeSpan.FromSeconds(request.TimeoutSeconds), cancellationToken);
            // Upstream BenchmarkRunController counts StdRepeat as total requests and
            // discards only request 1 when there is more than one request.
            if (!warmup) samples.Add(sample);
        }
        if (samples.Count == 0) throw new InvalidDataException("Benchmark produced no measured samples.");
        var pp = samples.Average(sample => sample.PrefillTokensPerSecond);
        var tg = samples.Average(sample => sample.DecodeTokensPerSecond);
        var ttft = samples.Average(sample => sample.PromptMilliseconds);
        var ppDeviation = Math.Sqrt(samples.Average(sample => Math.Pow(sample.PrefillTokensPerSecond - pp, 2)));
        var tgDeviation = Math.Sqrt(samples.Average(sample => Math.Pow(sample.DecodeTokensPerSecond - tg, 2)));
        var ttftDeviation = Math.Sqrt(samples.Average(sample => Math.Pow(sample.PromptMilliseconds - ttft, 2)));
        watch.Stop();
        var rawMetrics = await _probe.TryReadMetricsAsync(endpoint, cancellationToken);
        var run = new StoredBenchmarkRun(
            Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, request.ProfileId,
            request.ProfileName, request.ModelAlias, request.ProfileSha256,
            request.PromptTokens, request.OutputTokens, request.Repeats,
            samples.Count, pp, tg, ttft, ppDeviation, tgDeviation, ttftDeviation,
            watch.Elapsed.TotalSeconds, samples);
        await _store.SaveAsync(run, rawMetrics, cancellationToken);
        progress?.Report(new BenchmarkProgress(request.Repeats, request.Repeats, "Готово"));
        return run;
    }
}

public sealed record BenchmarkRunRequest(string ProfileId, string ProfileName, string ModelAlias,
    string ApiBaseUrl, string ProfileSha256, int PromptTokens, int OutputTokens, int Repeats,
    int TimeoutSeconds)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(ProfileId) || ProfileId.Length > 80 ||
            ProfileId.Any(ch => !char.IsLetterOrDigit(ch) && ch is not ('-' or '_')))
            throw new ArgumentException("Invalid profile ID.");
        if (string.IsNullOrWhiteSpace(ModelAlias) || ModelAlias.Length > 160)
            throw new ArgumentException("Invalid model alias.");
        if (PromptTokens is < 1 or > 200000 || OutputTokens is < 1 or > 4096 ||
            Repeats is < 1 or > 10 || TimeoutSeconds is < 5 or > 3600)
            throw new ArgumentOutOfRangeException(nameof(PromptTokens), "Benchmark parameters are out of range.");
        _ = HttpBenchmarkProbe.CompletionUrl(new Uri(ApiBaseUrl, UriKind.Absolute));
        if (ProfileSha256.Length != 64 || !ProfileSha256.All(Uri.IsHexDigit))
            throw new ArgumentException("Invalid profile fingerprint.");
    }

    public static string Fingerprint(string profileJson) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(profileJson)));
}

public sealed record BenchmarkProgress(int Completed, int Total, string Phase);
public sealed record StoredBenchmarkRun(string Id, DateTimeOffset CompletedAt, string ProfileId,
    string ProfileName, string ModelAlias, string ProfileSha256, int PromptTokens,
    int OutputTokens, int Repeats, int MeasuredRepeats,
    double PrefillTokensPerSecond, double DecodeTokensPerSecond, double TimeToFirstTokenMs,
    double PrefillStdDev, double DecodeStdDev, double TimeToFirstTokenStdDev,
    double DurationSeconds, IReadOnlyList<BenchmarkSample> Samples);
