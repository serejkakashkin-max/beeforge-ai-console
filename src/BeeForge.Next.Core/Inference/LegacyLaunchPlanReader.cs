using System.Diagnostics;
using System.Text.Json;

namespace BeeForge.Next.Core.Inference;

/// <summary>
/// Read-only compatibility adapter: argv still comes from the proven BeeForge
/// PowerShell module. It does not start or stop a server.
/// </summary>
public sealed class LegacyLaunchPlanReader
{
    public static async Task<LegacyLaunchPlan> ReadAsync(string scriptPath, string profileStore,
        string profileId, CancellationToken cancellationToken = default)
    {
        var start = new ProcessStartInfo("pwsh")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var value in new[] { "-NoProfile", "-File", Path.GetFullPath(scriptPath),
            "-ProfileStore", Path.GetFullPath(profileStore), "-ProfileId", profileId })
            start.ArgumentList.Add(value);
        using var process = Process.Start(start) ?? throw new IOException("PowerShell could not be started.");
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(10));
            var stdoutTask = process.StandardOutput.ReadToEndAsync(timeout.Token);
            var stderrTask = process.StandardError.ReadToEndAsync(timeout.Token);
            await process.WaitForExitAsync(timeout.Token);
            var stdout = await stdoutTask;
            var stderr = await stderrTask;
            if (process.ExitCode != 0)
                throw new InvalidDataException("Legacy launch-plan generator failed: " + SanitizeError(stderr));
            var plan = JsonSerializer.Deserialize<LegacyLaunchPlan>(stdout,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (plan is null || plan.Arguments is null || plan.Mode is not ("LocalHost" or "RemoteClient"))
                throw new InvalidDataException("Legacy launch-plan generator returned an invalid plan.");
            if (plan.Mode == "RemoteClient" && plan.Arguments.Count != 0)
                throw new InvalidDataException("Remote profile must not contain local launch arguments.");
            return plan;
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            throw;
        }
    }

    private static string SanitizeError(string message) =>
        message.Contains("Requested profile was not found", StringComparison.Ordinal)
            ? "Requested profile was not found" : "See local diagnostic output; details were not exposed to the UI.";
}

public sealed record LegacyLaunchPlan(string Mode, string ServerPath, string Alias,
    IReadOnlyList<string> Arguments);
