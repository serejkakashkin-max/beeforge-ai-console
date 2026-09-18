using System.Text.Json;
using System.Text;

namespace BeeForge.Next.Core.Benchmarking;

/// <summary>Private, bounded history for comparable standard workload runs.</summary>
public sealed class BenchmarkRunStore
{
    private readonly string _root;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public BenchmarkRunStore(string beeForgeRoot) =>
        _root = Path.Combine(Path.GetFullPath(beeForgeRoot), "benchmarks", "next");

    public string RootDirectory => _root;

    public Task SaveAsync(StoredBenchmarkRun run, CancellationToken cancellationToken = default) =>
        SaveAsync(run, rawMetrics: null, cancellationToken);

    public async Task SaveAsync(StoredBenchmarkRun run, string? rawMetrics,
        CancellationToken cancellationToken = default)
    {
        if (!SafeId(run.ProfileId) || !SafeId(run.Id))
            throw new InvalidDataException("Unsafe benchmark identifier.");
        var profileDirectory = Path.Combine(_root, run.ProfileId);
        var directory = Path.Combine(profileDirectory, run.Id);
        if (Directory.Exists(directory))
            throw new IOException("Benchmark run already exists.");
        Directory.CreateDirectory(profileDirectory);
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "run.json");
        var temporary = path + ".tmp";
        try
        {
            await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(run, JsonOptions),
                cancellationToken);
            File.Move(temporary, path);
            await File.WriteAllTextAsync(Path.Combine(directory, "report.md"),
                RenderRunReport(run), new UTF8Encoding(false), cancellationToken);
            if (!string.IsNullOrWhiteSpace(rawMetrics))
                await File.WriteAllTextAsync(Path.Combine(directory, "metrics.prom"), rawMetrics,
                    new UTF8Encoding(false), cancellationToken);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
            if (!File.Exists(path) && Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    public IReadOnlyList<StoredBenchmarkRun> Load(string? profileId = null, int limit = 100)
    {
        if (limit is < 1 or > 1000) throw new ArgumentOutOfRangeException(nameof(limit));
        if (profileId is not null && !SafeId(profileId)) throw new ArgumentException("Invalid profile ID.");
        if (!Directory.Exists(_root)) return Array.Empty<StoredBenchmarkRun>();
        var directories = profileId is null ? Directory.EnumerateDirectories(_root)
            : new[] { Path.Combine(_root, profileId) };
        var result = new List<StoredBenchmarkRun>();
        foreach (var directory in directories)
        {
            if (!Directory.Exists(directory)) continue;
            foreach (var runDirectory in Directory.EnumerateDirectories(directory))
            {
                var path = Path.Combine(runDirectory, "run.json");
                TryLoad(path, Path.GetFileName(directory), result);
            }
            // Compatibility with BeeForge Next benchmark files written before the
            // upstream directory layout was adopted.
            foreach (var path in Directory.EnumerateFiles(directory, "*.json"))
                TryLoad(path, Path.GetFileName(directory), result);
        }
        return result.OrderByDescending(run => run.CompletedAt).Take(limit).ToArray();
    }

    public string? GetRunDirectory(StoredBenchmarkRun run)
    {
        if (!SafeId(run.ProfileId) || !SafeId(run.Id)) return null;
        var path = Path.Combine(_root, run.ProfileId, run.Id);
        return Directory.Exists(path) ? path : null;
    }

    private static void TryLoad(string path, string expectedProfileId, List<StoredBenchmarkRun> result)
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 256 * 1024) return;
            var run = JsonSerializer.Deserialize<StoredBenchmarkRun>(File.ReadAllText(path));
            if (run is not null && run.ProfileId == expectedProfileId) result.Add(run);
        }
        catch (Exception) { /* A damaged run must not hide other history. */ }
    }

    private static string RenderRunReport(StoredBenchmarkRun run)
    {
        var builder = new StringBuilder();
        builder.AppendLine($"# Benchmark: {run.ProfileName}");
        builder.AppendLine();
        builder.AppendLine($"- Date: {run.CompletedAt:O}");
        builder.AppendLine($"- Model: {run.ModelAlias}");
        builder.AppendLine($"- Workload: {run.PromptTokens} prompt / {run.OutputTokens} generation tokens");
        builder.AppendLine($"- Requests: {run.Repeats} total, {run.MeasuredRepeats} measured");
        builder.AppendLine($"- Prompt: {run.PrefillTokensPerSecond:0.00} tok/s (σ {run.PrefillStdDev:0.00})");
        builder.AppendLine($"- Generation: {run.DecodeTokensPerSecond:0.00} tok/s (σ {run.DecodeStdDev:0.00})");
        builder.AppendLine($"- TTFT: {run.TimeToFirstTokenMs:0.00} ms (σ {run.TimeToFirstTokenStdDev:0.00})");
        builder.AppendLine($"- Duration: {run.DurationSeconds:0.00} s");
        builder.AppendLine($"- Profile fingerprint: {run.ProfileSha256}");
        return builder.ToString();
    }

    private static bool SafeId(string value) => value.Length is > 0 and <= 80 &&
        value.All(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_');
}
