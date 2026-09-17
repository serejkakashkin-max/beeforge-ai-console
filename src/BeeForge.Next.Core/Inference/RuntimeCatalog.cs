using System.Diagnostics;
using System.Text.Json;

namespace BeeForge.Next.Core.Inference;

public sealed record RuntimeInstall(string Provider, string Version, string ServerPath, string Detail);

public sealed class RuntimeCatalog
{
    private readonly string _root;
    public RuntimeCatalog(string root) => _root = Path.GetFullPath(root);

    public IReadOnlyList<RuntimeInstall> ListInstalled()
    {
        var runtimeRoot = Path.Combine(_root, "runtime");
        if (!Directory.Exists(runtimeRoot)) return Array.Empty<RuntimeInstall>();
        var result = new List<RuntimeInstall>();
        foreach (var server in Directory.EnumerateFiles(runtimeRoot, "llama-server.exe", SearchOption.AllDirectories))
        {
            var directory = Path.GetDirectoryName(server)!;
            var manifest = Path.Combine(directory, "beeforge-runtime.json");
            if (File.Exists(manifest))
            {
                try
                {
                    using var json = JsonDocument.Parse(File.ReadAllText(manifest));
                    var root = json.RootElement;
                    var product = root.TryGetProperty("product", out var p) ? p.GetString() ?? "BeeLlama" : "BeeLlama";
                    var version = root.TryGetProperty("version", out var v) ? v.GetString() ?? "unknown" : "unknown";
                    var cuda = root.TryGetProperty("cudaVersion", out var c) ? c.GetString() : null;
                    result.Add(new RuntimeInstall(product, version, server,
                        string.IsNullOrWhiteSpace(cuda) ? "managed" : $"CUDA {cuda}"));
                    continue;
                }
                catch (JsonException) { }
            }
            result.Add(new RuntimeInstall("Custom llama-server", "unknown", server, "unmanaged"));
        }
        return result.OrderBy(r => r.Provider).ThenByDescending(r => r.Version, StringComparer.OrdinalIgnoreCase).ToArray();
    }
}

public sealed class RuntimeInstaller
{
    private readonly string _scriptPath;
    public RuntimeInstaller(string root)
    {
        _scriptPath = Path.Combine(Path.GetFullPath(root), "scripts", "Install-BeeLlamaRuntime.ps1");
        if (!File.Exists(_scriptPath)) throw new FileNotFoundException("BeeLlama installer was not found.", _scriptPath);
    }

    public async Task InstallBeeLlamaAsync(string version = "v0.4.6", string cuda = "13.3",
        CancellationToken cancellationToken = default)
    {
        if (!System.Text.RegularExpressions.Regex.IsMatch(version, "^v\\d+\\.\\d+\\.\\d+$"))
            throw new ArgumentException("Invalid BeeLlama version.", nameof(version));
        if (cuda is not ("13.3" or "12.4")) throw new ArgumentException("Unsupported CUDA version.", nameof(cuda));
        var start = new ProcessStartInfo("pwsh")
        {
            UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true
        };
        foreach (var arg in new[] { "-NoProfile", "-File", _scriptPath, "-Version", version, "-CudaVersion", cuda })
            start.ArgumentList.Add(arg);
        using var process = Process.Start(start) ?? throw new IOException("PowerShell could not be started.");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(10));
        try
        {
            var stdout = process.StandardOutput.ReadToEndAsync(timeout.Token);
            var stderr = process.StandardError.ReadToEndAsync(timeout.Token);
            await process.WaitForExitAsync(timeout.Token);
            _ = await stdout; _ = await stderr;
            if (process.ExitCode != 0) throw new IOException("Runtime installation failed. See BeeForge installer output.");
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            throw;
        }
    }
}
