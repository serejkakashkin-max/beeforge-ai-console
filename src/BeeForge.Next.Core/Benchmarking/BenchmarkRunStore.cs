using System.Text.Json;

namespace BeeForge.Next.Core.Benchmarking;

/// <summary>Private, bounded history for comparable standard workload runs.</summary>
public sealed class BenchmarkRunStore
{
    private readonly string _root;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public BenchmarkRunStore(string beeForgeRoot) =>
        _root = Path.Combine(Path.GetFullPath(beeForgeRoot), "benchmarks", "next");

    public async Task SaveAsync(StoredBenchmarkRun run, CancellationToken cancellationToken = default)
    {
        if (!SafeId(run.ProfileId) || !SafeId(run.Id))
            throw new InvalidDataException("Unsafe benchmark identifier.");
        var directory = Path.Combine(_root, run.ProfileId);
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, run.Id + ".json");
        var temporary = path + ".tmp";
        if (File.Exists(path) || File.Exists(temporary))
            throw new IOException("Benchmark run already exists.");
        try
        {
            await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(run, JsonOptions),
                cancellationToken);
            File.Move(temporary, path);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
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
            foreach (var path in Directory.EnumerateFiles(directory, "*.json"))
            {
                try
                {
                    if (new FileInfo(path).Length > 128 * 1024) continue;
                    var run = JsonSerializer.Deserialize<StoredBenchmarkRun>(File.ReadAllText(path));
                    if (run is not null && run.ProfileId == Path.GetFileName(directory)) result.Add(run);
                }
                catch (Exception) { /* A damaged run must not hide other history. */ }
            }
        }
        return result.OrderByDescending(run => run.CompletedAt).Take(limit).ToArray();
    }

    private static bool SafeId(string value) => value.Length is > 0 and <= 80 &&
        value.All(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_');
}
