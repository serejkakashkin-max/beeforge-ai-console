using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace BeeForge.Next.Core.Inference;

public sealed record HfRepo(string Id, long Downloads)
{
    public override string ToString() => $"{Id} · {Downloads:N0} downloads";
}

public sealed record HfFile(string Path, long SizeBytes)
{
    public override string ToString() => $"{Path} · {SizeBytes / 1073741824.0:0.00} GiB";
}

public sealed record HfDownloadProgress(long BytesDone, long BytesTotal)
{
    public double Percent => BytesTotal > 0 ? Math.Clamp(BytesDone * 100.0 / BytesTotal, 0, 100) : 0;
}

public sealed class HuggingFaceService
{
    private readonly HttpClient _http;
    public HuggingFaceService(HttpMessageHandler? handler = null) =>
        _http = handler is null ? new HttpClient { Timeout = TimeSpan.FromSeconds(45) } : new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(45) };

    public static string SearchUrl(string query) =>
        "https://huggingface.co/api/models?search=" + Uri.EscapeDataString(query ?? "") +
        "&filter=gguf&sort=downloads&direction=-1&limit=30";

    public static string TreeUrl(string repo) =>
        "https://huggingface.co/api/models/" + EscapeRepo(repo) + "/tree/main?recursive=true&expand=false";

    public static string ResolveUrl(string repo, string path) =>
        "https://huggingface.co/" + EscapeRepo(repo) + "/resolve/main/" +
        string.Join('/', path.Split('/').Select(Uri.EscapeDataString));

    public async Task<IReadOnlyList<HfRepo>> SearchAsync(string query, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(query) || query.Length > 200) return Array.Empty<HfRepo>();
        using var request = CreateRequest(HttpMethod.Get, SearchUrl(query));
        using var response = await _http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(cancellationToken));
        var result = new List<HfRepo>();
        foreach (var item in doc.RootElement.EnumerateArray())
        {
            if (!item.TryGetProperty("id", out var idNode)) continue;
            var id = idNode.GetString();
            if (string.IsNullOrWhiteSpace(id)) continue;
            var downloads = item.TryGetProperty("downloads", out var d) && d.TryGetInt64(out var n) ? n : 0;
            result.Add(new HfRepo(id, downloads));
        }
        return result;
    }

    public async Task<IReadOnlyList<HfFile>> ListGgufAsync(string repo, CancellationToken cancellationToken = default)
    {
        ValidateRepo(repo);
        using var request = CreateRequest(HttpMethod.Get, TreeUrl(repo));
        using var response = await _http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(cancellationToken));
        var result = new List<HfFile>();
        foreach (var item in doc.RootElement.EnumerateArray())
        {
            var path = item.TryGetProperty("path", out var p) ? p.GetString() : null;
            if (string.IsNullOrWhiteSpace(path) || !path.EndsWith(".gguf", StringComparison.OrdinalIgnoreCase)) continue;
            var size = item.TryGetProperty("size", out var s) && s.TryGetInt64(out var n) ? n : 0;
            result.Add(new HfFile(path, size));
        }
        return result.OrderBy(x => x.Path, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    public async Task<string> DownloadAsync(string repo, HfFile file, string targetDirectory,
        IProgress<HfDownloadProgress>? progress = null, CancellationToken cancellationToken = default)
    {
        ValidateRepo(repo);
        var fileName = Path.GetFileName(file.Path);
        if (string.IsNullOrWhiteSpace(fileName) || !fileName.EndsWith(".gguf", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Only GGUF files can be downloaded here.");
        var directory = Path.GetFullPath(targetDirectory);
        Directory.CreateDirectory(directory);
        var target = Path.Combine(directory, fileName);
        var part = target + ".part";
        var have = File.Exists(part) ? new FileInfo(part).Length : 0;
        if (file.SizeBytes > 0 && have > file.SizeBytes) { File.Delete(part); have = 0; }
        if (File.Exists(target) && (file.SizeBytes <= 0 || new FileInfo(target).Length == file.SizeBytes)) return target;

        using var request = CreateRequest(HttpMethod.Get, ResolveUrl(repo, file.Path));
        if (have > 0) request.Headers.Range = new RangeHeaderValue(have, null);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (have > 0 && response.StatusCode != HttpStatusCode.PartialContent)
        {
            response.Dispose();
            File.Delete(part);
            return await DownloadAsync(repo, file, targetDirectory, progress, cancellationToken);
        }
        response.EnsureSuccessStatusCode();
        var total = file.SizeBytes > 0 ? file.SizeBytes : have + (response.Content.Headers.ContentLength ?? 0);
        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var output = new FileStream(part, have > 0 ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.None,
            1024 * 1024, FileOptions.Asynchronous);
        var buffer = new byte[1024 * 1024];
        var done = have;
        while (true)
        {
            var read = await input.ReadAsync(buffer, cancellationToken);
            if (read == 0) break;
            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            done += read;
            progress?.Report(new HfDownloadProgress(done, total));
        }
        await output.FlushAsync(cancellationToken);
        if (file.SizeBytes > 0 && done != file.SizeBytes) throw new IOException("Downloaded GGUF size does not match Hugging Face metadata.");
        File.Move(part, target, true);
        return target;
    }

    private HttpRequestMessage CreateRequest(HttpMethod method, string url)
    {
        var request = new HttpRequestMessage(method, url);
        request.Headers.UserAgent.ParseAdd("BeeForge-Next/1.0");
        var token = ResolveToken();
        if (!string.IsNullOrWhiteSpace(token)) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    private static string? ResolveToken()
    {
        foreach (var name in new[] { "HF_TOKEN", "HUGGING_FACE_HUB_TOKEN", "HUGGINGFACEHUB_API_TOKEN" })
        {
            var value = Environment.GetEnvironmentVariable(name);
            if (!string.IsNullOrWhiteSpace(value)) return value.Trim();
        }
        return null;
    }

    private static string EscapeRepo(string repo)
    {
        ValidateRepo(repo);
        return string.Join('/', repo.Split('/').Select(Uri.EscapeDataString));
    }

    private static void ValidateRepo(string repo)
    {
        if (string.IsNullOrWhiteSpace(repo) || repo.Length > 300 || repo.Count(c => c == '/') != 1 || repo.Contains("..", StringComparison.Ordinal))
            throw new ArgumentException("Invalid Hugging Face repository id.", nameof(repo));
    }
}
