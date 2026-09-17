using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace BeeForge.Next.Core.Inference;

/// <summary>
/// Read-only runtime compatibility preflight. It never starts llama-server;
/// the selected executable is invoked with --help only.
/// </summary>
public static partial class RuntimeCapabilityProbe
{
    public static async Task<RuntimeCapabilityReport> ProbeAsync(LegacyLaunchPlan plan,
        CancellationToken cancellationToken = default)
    {
        if (plan.Mode == "RemoteClient")
            return RuntimeCapabilityReport.Skipped("Удалённый профиль не использует локальный runtime.");
        if (string.IsNullOrWhiteSpace(plan.ServerPath) || !File.Exists(plan.ServerPath))
            return RuntimeCapabilityReport.Unavailable("Файл runtime не найден.");

        var start = new ProcessStartInfo(plan.ServerPath)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        start.ArgumentList.Add("--help");

        using var process = Process.Start(start);
        if (process is null)
            return RuntimeCapabilityReport.Unavailable("Не удалось запустить runtime для проверки --help.");

        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(10));
            var stdoutTask = process.StandardOutput.ReadToEndAsync(timeout.Token);
            var stderrTask = process.StandardError.ReadToEndAsync(timeout.Token);
            await process.WaitForExitAsync(timeout.Token);
            var help = (await stdoutTask) + Environment.NewLine + (await stderrTask);
            if (string.IsNullOrWhiteSpace(help))
                return RuntimeCapabilityReport.Unavailable("Runtime не вернул текст --help.");
            return Compare(plan.Arguments, help);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            return RuntimeCapabilityReport.Unavailable("Проверка --help превысила 10 секунд.");
        }
        catch (Exception)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            return RuntimeCapabilityReport.Unavailable("Не удалось проверить возможности выбранного runtime.");
        }
    }

    public static RuntimeCapabilityReport Compare(IReadOnlyList<string> arguments, string helpText)
    {
        var required = ExtractArgumentFlags(arguments);
        var supported = ExtractHelpFlags(helpText);
        if (supported.Count == 0)
            return RuntimeCapabilityReport.Unavailable("В --help не удалось распознать поддерживаемые параметры.");

        var missing = required.Where(flag => !supported.Contains(flag)).Order(StringComparer.Ordinal).ToArray();
        return new RuntimeCapabilityReport(true, false, required.Count, supported.Count, missing, null);
    }

    public static IReadOnlySet<string> ExtractArgumentFlags(IReadOnlyList<string> arguments)
    {
        var result = new HashSet<string>(StringComparer.Ordinal);
        foreach (var argument in arguments)
        {
            var match = ArgumentFlagRegex().Match(argument ?? string.Empty);
            if (match.Success) result.Add(match.Groups[1].Value);
        }
        return result;
    }

    public static IReadOnlySet<string> ExtractHelpFlags(string helpText)
    {
        var result = new HashSet<string>(StringComparer.Ordinal);
        foreach (Match match in HelpFlagRegex().Matches(helpText ?? string.Empty))
            result.Add(match.Groups[1].Value);
        return result;
    }

    [GeneratedRegex(@"^(--[A-Za-z][A-Za-z0-9-]*|-[A-Za-z])(?:=|$)", RegexOptions.CultureInvariant)]
    private static partial Regex ArgumentFlagRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9-])(--[A-Za-z][A-Za-z0-9-]*|-[A-Za-z])(?=[\s,=<\[]|$)",
        RegexOptions.CultureInvariant)]
    private static partial Regex HelpFlagRegex();
}

public sealed record RuntimeCapabilityReport(bool ProbeSucceeded, bool WasSkipped, int RequiredFlagCount,
    int SupportedFlagCount, IReadOnlyList<string> UnsupportedFlags, string? Message)
{
    public bool IsCompatible => ProbeSucceeded && UnsupportedFlags.Count == 0;

    public static RuntimeCapabilityReport Unavailable(string message) =>
        new(false, false, 0, 0, Array.Empty<string>(), message);

    public static RuntimeCapabilityReport Skipped(string message) =>
        new(false, true, 0, 0, Array.Empty<string>(), message);

    public string Describe()
    {
        if (WasSkipped || !ProbeSucceeded) return Message ?? "Проверка runtime недоступна.";
        if (UnsupportedFlags.Count == 0)
            return $"Совместимость runtime: OK · флагов профиля {RequiredFlagCount} · распознано в --help {SupportedFlagCount}.";

        var builder = new StringBuilder();
        builder.Append("Совместимость runtime: есть неподдерживаемые флаги профиля: ");
        builder.Append(string.Join(", ", UnsupportedFlags));
        builder.Append(". Это предупреждение Next; рабочий BeeForge выполнит собственную проверку перед запуском.");
        return builder.ToString();
    }
}
