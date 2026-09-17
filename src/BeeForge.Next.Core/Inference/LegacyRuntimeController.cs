using System.Diagnostics;
using System.Text.Json;

namespace BeeForge.Next.Core.Inference;

/// <summary>
/// Typed compatibility boundary for the current BeeForge runtime module.
/// The PowerShell module remains the sole owner of processes and state.
/// </summary>
public sealed class LegacyRuntimeController
{
    private readonly string _scriptPath;
    private readonly string _profileStore;

    public LegacyRuntimeController(string scriptPath, string profileStore)
    {
        _scriptPath = Path.GetFullPath(scriptPath);
        _profileStore = Path.GetFullPath(profileStore);
        if (!File.Exists(_scriptPath)) throw new FileNotFoundException("Runtime adapter script was not found.", _scriptPath);
    }

    public async Task<LegacyRuntimeStatus> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        using var output = await InvokeAsync("Status", null, TimeSpan.FromSeconds(20), cancellationToken);
        var root = output.RootElement;
        return new LegacyRuntimeStatus(
            GetBoolean(root, "Running"), GetBoolean(root, "Ready"), GetBoolean(root, "Remote"), GetBoolean(root, "Leased"),
            GetString(root, "Profile"), GetString(root, "Model"), GetString(root, "Message"),
            GetNullableInt(root, "Pid"), GetNullableDouble(root, "PromptTPS"), GetNullableDouble(root, "DecodeTPS"),
            GetNullableInt(root, "VramUsedMiB"), GetNullableInt(root, "VramTotalMiB"),
            GetNullableInt(root, "GpuUtil"), GetNullableInt(root, "GpuTempC"),
            GetNullableDouble(root, "RamUsedGiB"), GetNullableDouble(root, "RamTotalGiB"), GetNullableDouble(root, "RamAvailableGiB"),
            GetNullableInt(root, "Context"), GetNullableInt(root, "PromptTokens"), GetNullableInt(root, "DecodedTokens"),
            GetNullableInt(root, "SlotsBusy"), GetNullableInt(root, "SlotsTotal"),
            GetString(root, "Uptime"));
    }

    public async Task<LegacyRuntimeStatus> StartAsync(string profileId, CancellationToken cancellationToken = default)
    {
        using var output = await InvokeAsync("Start", profileId, null, cancellationToken);
        var root = output.RootElement;
        return new LegacyRuntimeStatus(
            GetBoolean(root, "Running"), GetBoolean(root, "Ready"), GetBoolean(root, "Remote"), GetBoolean(root, "Leased"),
            GetString(root, "Profile"), GetString(root, "Model"), GetString(root, "Message"),
            GetNullableInt(root, "Pid"), GetNullableDouble(root, "PromptTPS"), GetNullableDouble(root, "DecodeTPS"),
            GetNullableInt(root, "VramUsedMiB"), GetNullableInt(root, "VramTotalMiB"),
            GetNullableInt(root, "GpuUtil"), GetNullableInt(root, "GpuTempC"),
            GetNullableDouble(root, "RamUsedGiB"), GetNullableDouble(root, "RamTotalGiB"), GetNullableDouble(root, "RamAvailableGiB"),
            GetNullableInt(root, "Context"), GetNullableInt(root, "PromptTokens"), GetNullableInt(root, "DecodedTokens"),
            GetNullableInt(root, "SlotsBusy"), GetNullableInt(root, "SlotsTotal"),
            GetString(root, "Uptime"));
    }

    public async Task<string> StopAsync(string profileId, CancellationToken cancellationToken = default)
    {
        using var output = await InvokeAsync("Stop", profileId, TimeSpan.FromSeconds(30), cancellationToken);
        return GetString(output.RootElement, "Message");
    }

    public async Task<string> ConnectRemoteAsync(string profileId, CancellationToken cancellationToken = default)
    {
        using var output = await InvokeAsync("ConnectRemote", profileId, TimeSpan.FromSeconds(30), cancellationToken);
        return GetString(output.RootElement, "Message");
    }

    private async Task<JsonDocument> InvokeAsync(string action, string? profileId, TimeSpan? timeout,
        CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo("pwsh")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var value in new[] { "-NoProfile", "-File", _scriptPath, "-Action", action,
            "-ProfileStore", _profileStore }) start.ArgumentList.Add(value);
        if (profileId is not null)
        {
            start.ArgumentList.Add("-ProfileId");
            start.ArgumentList.Add(profileId);
        }
        using var process = Process.Start(start) ?? throw new IOException("PowerShell could not be started.");
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        if (timeout is not null) timeoutSource.CancelAfter(timeout.Value);
        try
        {
            var stdoutTask = process.StandardOutput.ReadToEndAsync(timeoutSource.Token);
            var stderrTask = process.StandardError.ReadToEndAsync(timeoutSource.Token);
            await process.WaitForExitAsync(timeoutSource.Token);
            var stdout = await stdoutTask;
            _ = await stderrTask; // Never forward runtime logs or paths to the UI.
            if (process.ExitCode != 0)
                throw new InvalidDataException("BeeForge runtime action failed. Check the existing BeeForge logs.");
            return JsonDocument.Parse(stdout);
        }
        catch (OperationCanceledException)
        {
            // A cancelled start may already have launched the model. Never kill
            // its owner halfway through readiness and OpenCode synchronization.
            if (action != "Start" && !process.HasExited) process.Kill(entireProcessTree: true);
            throw;
        }
    }

    private static bool GetBoolean(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;
    private static string GetString(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? "" : "";
    private static int? GetNullableInt(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number &&
        value.TryGetInt32(out var number) ? number : null;
    private static double? GetNullableDouble(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number &&
        value.TryGetDouble(out var number) ? number : null;
}

public sealed record LegacyRuntimeStatus(bool Running, bool Ready, bool Remote, bool Leased, string Profile,
    string Model, string Message, int? Pid, double? PromptTokensPerSecond, double? DecodeTokensPerSecond,
    int? VramUsedMiB, int? VramTotalMiB, int? GpuUtilization, int? GpuTemperatureC,
    double? RamUsedGiB, double? RamTotalGiB, double? RamAvailableGiB, int? ContextTokens,
    int? PromptTokens, int? DecodedTokens, int? SlotsBusy, int? SlotsTotal, string Uptime);
