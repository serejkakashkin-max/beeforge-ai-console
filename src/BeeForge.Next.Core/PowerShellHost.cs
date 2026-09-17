using System.Diagnostics;

namespace BeeForge.Next.Core;

/// <summary>
/// Resolves a real system PowerShell host for the desktop application.
/// The Codex/dev environment may expose a private pwsh on PATH that Explorer-launched
/// applications cannot see, so production code must not depend on PATH alone.
/// </summary>
public static class PowerShellHost
{
    public static string ResolveExecutable()
    {
        var configured = Environment.GetEnvironmentVariable("BEEFORGE_POWERSHELL");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
            return Path.GetFullPath(configured);

        if (OperatingSystem.IsWindows())
        {
            var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            if (!string.IsNullOrWhiteSpace(programFiles))
            {
                var pwsh = Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe");
                if (File.Exists(pwsh)) return pwsh;
            }

            var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            if (string.IsNullOrWhiteSpace(windows)) windows = Environment.GetEnvironmentVariable("SystemRoot") ?? string.Empty;
            if (!string.IsNullOrWhiteSpace(windows))
            {
                var windowsPowerShell = Path.Combine(windows, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
                if (File.Exists(windowsPowerShell)) return windowsPowerShell;
            }
        }

        // Non-Windows installations and unusual portable setups may legitimately
        // rely on PATH. Process.Start will provide the native error if it is absent.
        return "pwsh";
    }

    public static ProcessStartInfo CreateRedirected()
    {
        return new ProcessStartInfo(ResolveExecutable())
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
    }
}
