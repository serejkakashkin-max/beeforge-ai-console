using System.Net.Http.Json;
using System.Text.Json;

namespace BeeForge.Next.Core.Benchmarking;

/// <summary>
/// Repeatable HTTP workload adapted for BeeForge from the standard-workload
/// approach of LlamaServerLauncherAvalonia (MIT, pytraveler). It measures the
/// actual server endpoint, so BeeLlama-only runtime flags remain in effect.
/// </summary>
public sealed class HttpBenchmarkProbe
{
    private readonly HttpClient _http;

    public HttpBenchmarkProbe(HttpClient? httpClient = null) =>
        _http = httpClient ?? new HttpClient { Timeout = Timeout.InfiniteTimeSpan };

    public async Task VerifyModelAsync(Uri apiBase, string modelAlias, CancellationToken cancellationToken)
    {
        _ = CompletionUrl(apiBase);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(10));
        using var response = await _http.GetAsync(new Uri(apiBase.ToString().TrimEnd('/') + "/models"),
            timeout.Token);
        response.EnsureSuccessStatusCode();
        using var document = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(timeout.Token),
            cancellationToken: timeout.Token);
        if (!document.RootElement.TryGetProperty("data", out var entries) ||
            entries.ValueKind != JsonValueKind.Array ||
            !entries.EnumerateArray().Any(entry => entry.ValueKind == JsonValueKind.Object &&
                entry.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String &&
                id.GetString() == modelAlias))
            throw new InvalidDataException("The selected model alias is not active on this server.");
    }

    public async Task<BenchmarkSample> MeasureAsync(Uri apiBase, string modelAlias,
        int promptTokens, int outputTokens, TimeSpan timeout, CancellationToken cancellationToken)
    {
        if (promptTokens is < 256 or > 200000) throw new ArgumentOutOfRangeException(nameof(promptTokens));
        if (outputTokens is < 16 or > 4096) throw new ArgumentOutOfRangeException(nameof(outputTokens));
        if (timeout < TimeSpan.FromSeconds(30) || timeout > TimeSpan.FromHours(1))
            throw new ArgumentOutOfRangeException(nameof(timeout));
        if (string.IsNullOrWhiteSpace(modelAlias)) throw new ArgumentException("Model alias is required.", nameof(modelAlias));
        var completionUrl = CompletionUrl(apiBase);
        // llama-server's /completion is model-independent when exactly one model
        // is loaded; the caller must verify the active alias before measuring.
        var prompt = string.Join(' ', Enumerable.Repeat("word", promptTokens));
        var payload = new { prompt, n_predict = outputTokens, stream = false,
            cache_prompt = false, temperature = 0.0 };
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        linked.CancelAfter(timeout);
        using var response = await _http.PostAsJsonAsync(completionUrl, payload, linked.Token);
        response.EnsureSuccessStatusCode();
        using var document = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(linked.Token),
            cancellationToken: linked.Token);
        if (!document.RootElement.TryGetProperty("timings", out var timings) ||
            timings.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException("llama-server response has no timings object.");
        var pp = Number(timings, "prompt_per_second");
        var tg = Number(timings, "predicted_per_second");
        var promptCount = Integer(timings, "prompt_n");
        var outputCount = Integer(timings, "predicted_n");
        var promptMs = Number(timings, "prompt_ms");
        if (!double.IsFinite(promptMs) || promptMs < 0) promptMs = 0;
        if (!double.IsFinite(pp) || !double.IsFinite(tg) || pp <= 0 || tg <= 0 ||
            promptCount < 1 || outputCount < 16)
            throw new InvalidDataException("llama-server returned incomplete benchmark timings.");
        return new BenchmarkSample(pp, tg, promptCount, outputCount, promptMs);
    }

    public static Uri CompletionUrl(Uri apiBase)
    {
        if (!apiBase.IsAbsoluteUri || apiBase.Scheme is not ("http" or "https"))
            throw new ArgumentException("An absolute HTTP API URL is required.", nameof(apiBase));
        if (!(apiBase.IsLoopback && apiBase.Scheme == "http") &&
            !(apiBase.Scheme == "https" && apiBase.Host.EndsWith(".ts.net", StringComparison.OrdinalIgnoreCase)))
            throw new ArgumentException("Only local or private Tailscale endpoints are supported.", nameof(apiBase));
        if (!string.IsNullOrEmpty(apiBase.Query) || !string.IsNullOrEmpty(apiBase.Fragment))
            throw new ArgumentException("API URL must not contain query or fragment.", nameof(apiBase));
        var path = apiBase.AbsolutePath.TrimEnd('/');
        if (!path.EndsWith("/v1", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("API base URL must end in /v1.", nameof(apiBase));
        var root = apiBase.GetLeftPart(UriPartial.Authority) + path[..^3];
        return new Uri(root.TrimEnd('/') + "/completion", UriKind.Absolute);
    }

    private static double Number(JsonElement source, string name) =>
        source.TryGetProperty(name, out var element) && element.ValueKind == JsonValueKind.Number &&
        element.TryGetDouble(out var value) ? value : double.NaN;
    private static int Integer(JsonElement source, string name) =>
        source.TryGetProperty(name, out var element) && element.ValueKind == JsonValueKind.Number &&
        element.TryGetInt32(out var value) ? value : 0;
}

public sealed record BenchmarkSample(double PrefillTokensPerSecond, double DecodeTokensPerSecond,
    int PromptTokens, int OutputTokens, double PromptMilliseconds);
