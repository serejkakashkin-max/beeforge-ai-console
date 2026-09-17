using System.Security.Cryptography;
using System.Text;

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
        progress?.Report(new BenchmarkProgress(0, request.Repeats, "Разогрев"));
        // Like the upstream standard workload, the first pass is discarded.
        await _probe.MeasureAsync(endpoint, request.ModelAlias, request.PromptTokens,
            request.OutputTokens, TimeSpan.FromSeconds(request.TimeoutSeconds), cancellationToken);
        var samples = new List<BenchmarkSample>(request.Repeats);
        for (var i = 0; i < request.Repeats; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            progress?.Report(new BenchmarkProgress(i + 1, request.Repeats, "Измерение"));
            samples.Add(await _probe.MeasureAsync(endpoint, request.ModelAlias, request.PromptTokens,
                request.OutputTokens, TimeSpan.FromSeconds(request.TimeoutSeconds), cancellationToken));
        }
        var pp = samples.Average(sample => sample.PrefillTokensPerSecond);
        var tg = samples.Average(sample => sample.DecodeTokensPerSecond);
        var ppDeviation = Math.Sqrt(samples.Average(sample => Math.Pow(sample.PrefillTokensPerSecond - pp, 2)));
        var tgDeviation = Math.Sqrt(samples.Average(sample => Math.Pow(sample.DecodeTokensPerSecond - tg, 2)));
        var run = new StoredBenchmarkRun(
            Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, request.ProfileId,
            request.ProfileName, request.ModelAlias, request.ProfileSha256,
            request.PromptTokens, request.OutputTokens, request.Repeats,
            pp, tg, ppDeviation, tgDeviation, samples);
        await _store.SaveAsync(run, cancellationToken);
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
        if (PromptTokens is < 256 or > 200000 || OutputTokens is < 16 or > 4096 ||
            Repeats is < 2 or > 10 || TimeoutSeconds is < 30 or > 3600)
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
    int OutputTokens, int Repeats, double PrefillTokensPerSecond, double DecodeTokensPerSecond,
    double PrefillStdDev, double DecodeStdDev, IReadOnlyList<BenchmarkSample> Samples);
