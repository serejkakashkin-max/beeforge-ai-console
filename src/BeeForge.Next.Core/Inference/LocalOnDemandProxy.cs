using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using BeeForge.Next.Core.Profiles;

namespace BeeForge.Next.Core.Inference;

public sealed record ProxyProfile(string Id, string Name, string Alias, int Port);

public static class OpenAiProxyProtocol
{
    private static readonly HashSet<string> Paths = new(StringComparer.Ordinal)
    {
        "/v1/chat/completions", "/v1/completions", "/v1/embeddings", "/v1/rerank",
        "/rerank", "/completion", "/completions", "/infill", "/v1/messages"
    };

    public static string? ExtractModel(string body)
    {
        if (string.IsNullOrWhiteSpace(body)) return null;
        try
        {
            using var json = JsonDocument.Parse(body);
            return json.RootElement.ValueKind == JsonValueKind.Object &&
                json.RootElement.TryGetProperty("model", out var model) && model.ValueKind == JsonValueKind.String
                ? model.GetString() : null;
        }
        catch (JsonException) { return null; }
    }

    public static ProxyProfile? Match(string? requested, IReadOnlyList<ProxyProfile> profiles, string? fallbackId = null)
    {
        if (!string.IsNullOrWhiteSpace(requested))
        {
            var exact = profiles.FirstOrDefault(p => string.Equals(p.Alias, requested, StringComparison.Ordinal) ||
                string.Equals(p.Name, requested, StringComparison.Ordinal) || string.Equals(p.Id, requested, StringComparison.Ordinal));
            if (exact is not null) return exact;
            var ci = profiles.FirstOrDefault(p => string.Equals(p.Alias, requested, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(p.Name, requested, StringComparison.OrdinalIgnoreCase) || string.Equals(p.Id, requested, StringComparison.OrdinalIgnoreCase));
            if (ci is not null) return ci;
        }
        return string.IsNullOrWhiteSpace(fallbackId) ? null : profiles.FirstOrDefault(p => p.Id == fallbackId);
    }

    public static bool IsProxiedPath(string path) => Paths.Contains(path);

    public static IReadOnlyList<ProxyProfile> ReadProfiles(string profileStore)
    {
        var catalog = LegacyProfileCatalog.Load(profileStore);
        return catalog.Profiles.Where(p => p.ConnectionMode == "LocalHost").Select(p =>
        {
            using var json = JsonDocument.Parse(p.RawJson);
            var port = json.RootElement.TryGetProperty("port", out var value) && value.TryGetInt32(out var parsed)
                ? parsed : 8080;
            if (port is < 1 or > 65535) port = 8080;
            return new ProxyProfile(p.Id, string.IsNullOrWhiteSpace(p.Name) ? p.Id : p.Name,
                string.IsNullOrWhiteSpace(p.Alias) ? p.Id : p.Alias, port);
        }).ToArray();
    }
}

/// <summary>
/// Opt-in OpenAI-compatible model router. It binds strictly to loopback and delegates runtime
/// ownership to the existing BeeForge controller. No Tailscale/LAN listener is created.
/// </summary>
public sealed class LocalOnDemandProxy : IAsyncDisposable
{
    private const int MaxHeaderBytes = 64 * 1024;
    private const int MaxBodyBytes = 16 * 1024 * 1024;
    private readonly string _profileStore;
    private readonly LegacyRuntimeController _runtime;
    private readonly HttpClient _http = new() { Timeout = Timeout.InfiniteTimeSpan };
    private readonly SemaphoreSlim _swapLock = new(1, 1);
    private CancellationTokenSource? _cts;
    private TcpListener? _listener;
    private Task? _acceptLoop;
    private Task? _idleLoop;
    private string? _activeProfileId;
    private long _lastUseTicks;
    private int _inflight;
    private int _idleSeconds;

    public LocalOnDemandProxy(string profileStore, LegacyRuntimeController runtime)
    {
        _profileStore = Path.GetFullPath(profileStore);
        _runtime = runtime;
    }

    public bool IsRunning => _listener is not null;
    public int Port { get; private set; }
    public string Endpoint => $"http://127.0.0.1:{Port}/v1";

    public void Start(int port = 18080, int idleSeconds = 300)
    {
        if (_listener is not null) return;
        if (port is < 1024 or > 65535) throw new ArgumentOutOfRangeException(nameof(port));
        _idleSeconds = Math.Clamp(idleSeconds, 0, 86400);
        var listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        var cts = new CancellationTokenSource();
        _listener = listener;
        _cts = cts;
        Port = port;
        _acceptLoop = AcceptLoopAsync(listener, cts.Token);
        _idleLoop = IdleLoopAsync(cts.Token);
    }

    public async Task StopAsync(bool stopProxyOwnedModel = true)
    {
        var listener = _listener;
        var cts = _cts;
        _listener = null;
        _cts = null;
        if (listener is null) return;
        cts?.Cancel();
        try { listener.Stop(); } catch { }
        var tasks = new[] { _acceptLoop, _idleLoop }.Where(t => t is not null).Cast<Task>().ToArray();
        try { if (tasks.Length > 0) await Task.WhenAll(tasks).WaitAsync(TimeSpan.FromSeconds(3)); } catch { }
        _acceptLoop = null;
        _idleLoop = null;
        if (stopProxyOwnedModel && _activeProfileId is { } active)
        {
            try { await _runtime.StopAsync(active); } catch { }
        }
        _activeProfileId = null;
        Interlocked.Exchange(ref _lastUseTicks, 0);
        cts?.Dispose();
    }

    private async Task AcceptLoopAsync(TcpListener listener, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                var client = await listener.AcceptTcpClientAsync(cancellationToken);
                _ = HandleClientAsync(client, cancellationToken);
            }
            catch (OperationCanceledException) { break; }
            catch (ObjectDisposedException) { break; }
            catch { if (cancellationToken.IsCancellationRequested) break; }
        }
    }

    private async Task IdleLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try { await Task.Delay(1000, cancellationToken); } catch (OperationCanceledException) { break; }
            if (_idleSeconds <= 0 || _activeProfileId is null || Volatile.Read(ref _inflight) != 0) continue;
            var last = Interlocked.Read(ref _lastUseTicks);
            if (last == 0 || DateTime.UtcNow.Ticks - last < TimeSpan.FromSeconds(_idleSeconds).Ticks) continue;
            await _swapLock.WaitAsync(cancellationToken);
            try
            {
                if (_activeProfileId is { } active && Volatile.Read(ref _inflight) == 0)
                {
                    try { await _runtime.StopAsync(active, cancellationToken); } catch { }
                    _activeProfileId = null;
                    Interlocked.Exchange(ref _lastUseTicks, 0);
                }
            }
            finally { _swapLock.Release(); }
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
    {
        using (client)
        await using (var stream = client.GetStream())
        {
            try
            {
                var request = await ReadRequestAsync(stream, cancellationToken);
                if (request is null) return;
                if (request.Path is "/health" or "/v1/health")
                {
                    await WriteJsonAsync(stream, "200 OK", "{\"status\":\"ok\"}", cancellationToken);
                    return;
                }
                var profiles = OpenAiProxyProtocol.ReadProfiles(_profileStore);
                if (request.Path is "/v1/models" or "/models")
                {
                    var data = profiles.Select(p => new { id = p.Alias, @object = "model", owned_by = "beeforge" }).ToArray();
                    await WriteJsonAsync(stream, "200 OK", JsonSerializer.Serialize(new { @object = "list", data }), cancellationToken);
                    return;
                }
                if (!OpenAiProxyProtocol.IsProxiedPath(request.Path))
                {
                    await WriteJsonAsync(stream, "404 Not Found", "{\"error\":\"not found\"}", cancellationToken);
                    return;
                }
                var bodyText = request.Body.Length == 0 ? "" : Encoding.UTF8.GetString(request.Body);
                var catalog = LegacyProfileCatalog.Load(_profileStore);
                var profile = OpenAiProxyProtocol.Match(OpenAiProxyProtocol.ExtractModel(bodyText), profiles, catalog.ActiveProfileId);
                if (profile is null)
                {
                    await WriteJsonAsync(stream, "400 Bad Request", "{\"error\":\"no matching local profile\"}", cancellationToken);
                    return;
                }
                Interlocked.Increment(ref _inflight);
                try
                {
                    await EnsureRunningAsync(profile, cancellationToken);
                    Interlocked.Exchange(ref _lastUseTicks, DateTime.UtcNow.Ticks);
                    await ProxyAsync(stream, request, profile.Port, cancellationToken);
                }
                finally
                {
                    Interlocked.Exchange(ref _lastUseTicks, DateTime.UtcNow.Ticks);
                    Interlocked.Decrement(ref _inflight);
                }
            }
            catch (Exception)
            {
                try { await WriteJsonAsync(stream, "502 Bad Gateway", "{\"error\":\"proxy request failed\"}", cancellationToken); } catch { }
            }
        }
    }

    private async Task EnsureRunningAsync(ProxyProfile profile, CancellationToken cancellationToken)
    {
        if (_activeProfileId == profile.Id) return;
        await _swapLock.WaitAsync(cancellationToken);
        try
        {
            if (_activeProfileId == profile.Id) return;
            var status = await _runtime.StartAsync(profile.Id, cancellationToken);
            if (!status.Ready) throw new IOException("BeeForge runtime did not become ready.");
            _activeProfileId = profile.Id;
        }
        finally { _swapLock.Release(); }
    }

    private async Task ProxyAsync(NetworkStream client, ProxyRequest request, int upstreamPort,
        CancellationToken cancellationToken)
    {
        var url = $"http://127.0.0.1:{upstreamPort}{request.Path}{request.Query}";
        using var message = new HttpRequestMessage(new HttpMethod(request.Method), url);
        if (request.Body.Length > 0)
        {
            message.Content = new ByteArrayContent(request.Body);
            if (request.Headers.TryGetValue("Content-Type", out var type) && MediaTypeHeaderValue.TryParse(type, out var mediaType))
                message.Content.Headers.ContentType = mediaType;
            else message.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        }
        using var response = await _http.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        var headers = new StringBuilder($"HTTP/1.1 {(int)response.StatusCode} {response.ReasonPhrase}\r\n");
        foreach (var header in response.Headers.Concat(response.Content.Headers))
        {
            if (header.Key.Equals("Transfer-Encoding", StringComparison.OrdinalIgnoreCase) ||
                header.Key.Equals("Connection", StringComparison.OrdinalIgnoreCase) ||
                header.Key.Equals("Content-Length", StringComparison.OrdinalIgnoreCase)) continue;
            headers.Append(header.Key).Append(": ").Append(string.Join(", ", header.Value)).Append("\r\n");
        }
        headers.Append("Connection: close\r\n\r\n");
        await client.WriteAsync(Encoding.ASCII.GetBytes(headers.ToString()), cancellationToken);
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await source.CopyToAsync(client, cancellationToken);
        await client.FlushAsync(cancellationToken);
    }

    private static async Task<ProxyRequest?> ReadRequestAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        using var buffer = new MemoryStream();
        var chunk = new byte[8192];
        var end = -1;
        while (buffer.Length < MaxHeaderBytes)
        {
            var read = await stream.ReadAsync(chunk, cancellationToken);
            if (read == 0) break;
            buffer.Write(chunk, 0, read);
            end = FindHeaderEnd(buffer.GetBuffer(), (int)buffer.Length);
            if (end >= 0) break;
        }
        if (end < 0) return null;
        var raw = buffer.GetBuffer();
        var head = Encoding.UTF8.GetString(raw, 0, end).Replace("\r\n", "\n").Split('\n');
        var requestLine = head[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (requestLine.Length < 2) return null;
        var target = requestLine[1];
        var q = target.IndexOf('?');
        var path = q < 0 ? target : target[..q];
        var query = q < 0 ? "" : target[q..];
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in head.Skip(1))
        {
            var colon = line.IndexOf(':');
            if (colon > 0) headers[line[..colon].Trim()] = line[(colon + 1)..].Trim();
        }
        var contentLength = headers.TryGetValue("Content-Length", out var lengthText) && int.TryParse(lengthText, out var length)
            ? length : 0;
        if (contentLength is < 0 or > MaxBodyBytes) return null;
        var body = new byte[contentLength];
        var bodyStart = end + 4;
        var already = Math.Min(contentLength, (int)buffer.Length - bodyStart);
        if (already > 0) Array.Copy(raw, bodyStart, body, 0, already);
        var offset = already;
        while (offset < contentLength)
        {
            var read = await stream.ReadAsync(body.AsMemory(offset, contentLength - offset), cancellationToken);
            if (read == 0) return null;
            offset += read;
        }
        return new ProxyRequest(requestLine[0], path, query, headers, body);
    }

    private static int FindHeaderEnd(byte[] data, int length)
    {
        for (var i = 0; i + 3 < length; i++)
            if (data[i] == '\r' && data[i + 1] == '\n' && data[i + 2] == '\r' && data[i + 3] == '\n') return i;
        return -1;
    }

    private static async Task WriteJsonAsync(NetworkStream stream, string status, string body,
        CancellationToken cancellationToken)
    {
        var bytes = Encoding.UTF8.GetBytes(body);
        var head = Encoding.ASCII.GetBytes($"HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n");
        await stream.WriteAsync(head, cancellationToken);
        await stream.WriteAsync(bytes, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
        _http.Dispose();
        _swapLock.Dispose();
    }

    private sealed record ProxyRequest(string Method, string Path, string Query,
        Dictionary<string, string> Headers, byte[] Body);
}
