using System.IO.Compression;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace BeeForge.Next.Core.Inference;

public enum LlamaRuntimeBackend
{
    Cpu,
    Cuda,
    Vulkan,
    Hip,
    Sycl
}

public sealed record UpstreamReleaseAsset(string Name, string Url, long Size, string? Digest);
public sealed record UpstreamRelease(string Tag, DateTimeOffset? PublishedAt, IReadOnlyList<UpstreamReleaseAsset> Assets);

/// <summary>
/// Windows-first upstream llama.cpp runtime manager. Installs into BeeForge's own runtime tree,
/// never changes an active profile and keeps the previous target directory as a rollback copy.
/// </summary>
public sealed class UpstreamLlamaRuntimeManager
{
    private static readonly Regex SafeTag = new("^[A-Za-z0-9._-]{1,80}$", RegexOptions.Compiled);
    private readonly string _runtimeRoot;
    private readonly HttpClient _http;

    public UpstreamLlamaRuntimeManager(string root, HttpClient? httpClient = null)
    {
        _runtimeRoot = Path.Combine(Path.GetFullPath(root), "runtime", "llama.cpp");
        _http = httpClient ?? new HttpClient { Timeout = TimeSpan.FromMinutes(30) };
        if (!_http.DefaultRequestHeaders.UserAgent.Any())
            _http.DefaultRequestHeaders.UserAgent.ParseAdd("BeeForge-Next/1.0");
    }

    public static string BackendLabel(LlamaRuntimeBackend backend) => backend switch
    {
        LlamaRuntimeBackend.Cuda => "CUDA",
        LlamaRuntimeBackend.Vulkan => "Vulkan",
        LlamaRuntimeBackend.Hip => "HIP",
        LlamaRuntimeBackend.Sycl => "SYCL",
        _ => "CPU"
    };

    public async Task<IReadOnlyList<UpstreamRelease>> GetReleasesAsync(int count = 10,
        CancellationToken cancellationToken = default)
    {
        count = Math.Clamp(count, 1, 20);
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page={count}");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var json = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var result = new List<UpstreamRelease>();
        foreach (var release in json.RootElement.EnumerateArray())
        {
            var tag = release.TryGetProperty("tag_name", out var tagNode) ? tagNode.GetString() ?? "" : "";
            if (!SafeTag.IsMatch(tag)) continue;
            DateTimeOffset? published = null;
            if (release.TryGetProperty("published_at", out var dateNode) &&
                DateTimeOffset.TryParse(dateNode.GetString(), out var parsed)) published = parsed;
            var assets = new List<UpstreamReleaseAsset>();
            if (release.TryGetProperty("assets", out var assetsNode))
            {
                foreach (var asset in assetsNode.EnumerateArray())
                {
                    var name = asset.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    var url = asset.TryGetProperty("browser_download_url", out var u) ? u.GetString() ?? "" : "";
                    var size = asset.TryGetProperty("size", out var s) && s.TryGetInt64(out var bytes) ? bytes : 0;
                    var digest = asset.TryGetProperty("digest", out var d) ? d.GetString() : null;
                    if (name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) && Uri.TryCreate(url, UriKind.Absolute, out _))
                        assets.Add(new UpstreamReleaseAsset(name, url, size, digest));
                }
            }
            result.Add(new UpstreamRelease(tag, published, assets));
        }
        return result;
    }

    public static UpstreamReleaseAsset? SelectWindowsAsset(IEnumerable<UpstreamReleaseAsset> assets,
        LlamaRuntimeBackend backend)
    {
        static bool WinZip(string name) => name.Contains("win", StringComparison.OrdinalIgnoreCase) &&
            name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) &&
            !name.StartsWith("cudart-", StringComparison.OrdinalIgnoreCase);

        var candidates = assets.Where(a => WinZip(a.Name)).ToArray();
        bool Matches(UpstreamReleaseAsset asset)
        {
            var n = asset.Name.ToLowerInvariant();
            return backend switch
            {
                LlamaRuntimeBackend.Cuda => n.Contains("cuda") || n.Contains("cu11") || n.Contains("cu12") || n.Contains("cu13"),
                LlamaRuntimeBackend.Vulkan => n.Contains("vulkan"),
                LlamaRuntimeBackend.Hip => n.Contains("hip") || n.Contains("rocm"),
                LlamaRuntimeBackend.Sycl => n.Contains("sycl"),
                _ => !n.Contains("cuda") && !n.Contains("vulkan") && !n.Contains("hip") &&
                     !n.Contains("rocm") && !n.Contains("sycl")
            };
        }
        return candidates.Where(Matches).OrderByDescending(a => CpuPreference(a.Name)).FirstOrDefault();
    }

    public async Task<string> InstallAsync(UpstreamRelease release, LlamaRuntimeBackend backend,
        IProgress<double>? progress = null, CancellationToken cancellationToken = default)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Upstream runtime installer is Windows-first.");
        if (!SafeTag.IsMatch(release.Tag)) throw new ArgumentException("Unsafe release tag.", nameof(release));
        var asset = SelectWindowsAsset(release.Assets, backend) ??
            throw new InvalidOperationException($"Release {release.Tag} has no Windows {BackendLabel(backend)} asset.");
        var target = Path.Combine(_runtimeRoot, release.Tag, backend.ToString().ToLowerInvariant());
        var stage = target + ".installing";
        var backup = target + ".previous";
        var archive = Path.Combine(Path.GetTempPath(), $"beeforge-llama-{Guid.NewGuid():N}.zip");
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        TryDeleteDirectory(stage);
        Directory.CreateDirectory(stage);
        try
        {
            await DownloadAsync(asset, archive, progress, cancellationToken);
            ExtractZipSafely(archive, stage);
            var server = Directory.EnumerateFiles(stage, "llama-server.exe", SearchOption.AllDirectories).FirstOrDefault() ??
                throw new InvalidDataException("Downloaded archive does not contain llama-server.exe.");
            FlattenRuntime(stage, server);
            var finalServer = Path.Combine(stage, "llama-server.exe");
            if (!File.Exists(finalServer)) throw new InvalidDataException("llama-server.exe was not prepared.");
            var manifest = new
            {
                product = "llama.cpp",
                version = release.Tag,
                backend = BackendLabel(backend),
                source = "ggml-org/llama.cpp",
                asset = asset.Name,
                installedAt = DateTimeOffset.UtcNow
            };
            await File.WriteAllTextAsync(Path.Combine(stage, "beeforge-runtime.json"),
                JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }), cancellationToken);

            TryDeleteDirectory(backup);
            if (Directory.Exists(target)) Directory.Move(target, backup);
            try { Directory.Move(stage, target); }
            catch
            {
                if (Directory.Exists(backup) && !Directory.Exists(target)) Directory.Move(backup, target);
                throw;
            }
            progress?.Report(100);
            return Path.Combine(target, "llama-server.exe");
        }
        finally
        {
            TryDeleteDirectory(stage);
            try { if (File.Exists(archive)) File.Delete(archive); } catch { }
        }
    }

    public bool RestorePrevious(string tag, LlamaRuntimeBackend backend)
    {
        if (!SafeTag.IsMatch(tag)) return false;
        var target = Path.Combine(_runtimeRoot, tag, backend.ToString().ToLowerInvariant());
        var backup = target + ".previous";
        if (!Directory.Exists(backup) || !File.Exists(Path.Combine(backup, "llama-server.exe"))) return false;
        var swap = target + ".rollback-swap";
        TryDeleteDirectory(swap);
        try
        {
            if (Directory.Exists(target)) Directory.Move(target, swap);
            Directory.Move(backup, target);
            if (Directory.Exists(swap)) Directory.Move(swap, backup);
            return true;
        }
        catch
        {
            if (!Directory.Exists(target) && Directory.Exists(swap)) Directory.Move(swap, target);
            return false;
        }
    }

    private async Task DownloadAsync(UpstreamReleaseAsset asset, string path, IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        using var response = await _http.GetAsync(asset.Url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength ?? asset.Size;
        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1024 * 128, true);
        var buffer = new byte[1024 * 128];
        long readTotal = 0;
        int read;
        while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
        {
            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            readTotal += read;
            if (total > 0) progress?.Report(Math.Min(90, readTotal * 90.0 / total));
        }
        if (asset.Size > 0 && readTotal != asset.Size)
            throw new InvalidDataException($"Downloaded size mismatch for {asset.Name}.");
        if (!string.IsNullOrWhiteSpace(asset.Digest) && asset.Digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
        {
            await using var verify = File.OpenRead(path);
            var hash = Convert.ToHexString(await System.Security.Cryptography.SHA256.HashDataAsync(verify, cancellationToken));
            if (!hash.Equals(asset.Digest[7..], StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"SHA-256 mismatch for {asset.Name}.");
        }
    }

    private static void ExtractZipSafely(string archive, string target)
    {
        var targetFull = Path.GetFullPath(target) + Path.DirectorySeparatorChar;
        using var zip = ZipFile.OpenRead(archive);
        foreach (var entry in zip.Entries)
        {
            if (string.IsNullOrEmpty(entry.Name)) continue;
            var destination = Path.GetFullPath(Path.Combine(target, entry.FullName));
            if (!destination.StartsWith(targetFull, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Runtime archive contains an unsafe path.");
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            entry.ExtractToFile(destination, overwrite: true);
        }
    }

    private static void FlattenRuntime(string stage, string server)
    {
        var sourceDir = Path.GetDirectoryName(server)!;
        if (string.Equals(Path.GetFullPath(stage), Path.GetFullPath(sourceDir), StringComparison.OrdinalIgnoreCase)) return;
        foreach (var file in Directory.EnumerateFiles(sourceDir))
            File.Copy(file, Path.Combine(stage, Path.GetFileName(file)), overwrite: true);
    }

    private static int CpuPreference(string name)
    {
        var n = name.ToLowerInvariant();
        if (n.Contains("avx2")) return 4;
        if (n.Contains("avx512")) return 3;
        if (n.Contains("avx")) return 2;
        if (n.Contains("sse")) return 1;
        if (n.Contains("noavx")) return 0;
        return 3;
    }

    private static void TryDeleteDirectory(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); } catch { }
    }
}
