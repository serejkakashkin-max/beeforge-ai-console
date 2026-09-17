using System.Diagnostics;
using System.Text.Json;

namespace BeeForge.Next.Core.Workspace;

public enum ServiceAction
{
    TelegramStatus, TelegramStart, TelegramStop, RemoteStatus, RemoteEnable, RemoteDisable,
    RemoteInstallCommand, FullAccessStatus, FullAccessEnable, FullAccessDisable, SerenaProjects
}

/// <summary>Only explicit, allowlisted actions; credentials never cross this boundary.</summary>
public sealed class LegacyServiceController(string scriptPath, string profileStore)
{
    public async Task<JsonElement> InvokeAsync(ServiceAction action, string? profileId = null)
    {
        if (!Enum.IsDefined(action)) throw new ArgumentOutOfRangeException(nameof(action));
        var start = new ProcessStartInfo("pwsh") {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        foreach (var arg in new[] { "-NoProfile", "-File", Path.GetFullPath(scriptPath), "-Action", action.ToString(),
            "-ProfileStore", Path.GetFullPath(profileStore) }) start.ArgumentList.Add(arg);
        if (profileId is not null) { start.ArgumentList.Add("-ProfileId"); start.ArgumentList.Add(profileId); }
        using var process = Process.Start(start) ?? throw new IOException("Не удалось запустить службу BeeForge.");
        // Mutation lifetime is owned by the existing module: do not kill it between saving and rollback.
        var output = process.StandardOutput.ReadToEndAsync();
        var errors = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var text = await output;
        _ = await errors;
        if (process.ExitCode != 0) throw new IOException("Действие не выполнено. Проверьте настройки в рабочей консоли BeeForge; подробности могут содержать секреты и не выводятся здесь.");
        using var document = JsonDocument.Parse(text);
        return document.RootElement.Clone();
    }
}
