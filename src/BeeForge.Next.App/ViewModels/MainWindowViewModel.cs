using BeeForge.Next.Core.Profiles;

namespace BeeForge.Next.App.ViewModels;

public sealed class MainWindowViewModel
{
    private MainWindowViewModel(string status, string activeProfile, string mode,
        int profileCount, IReadOnlyList<string> profileNames)
    {
        Status = status;
        ActiveProfile = activeProfile;
        Mode = mode;
        ProfileCount = profileCount;
        ProfileNames = profileNames;
    }

    public string Status { get; }
    public string ActiveProfile { get; }
    public string Mode { get; }
    public int ProfileCount { get; }
    public IReadOnlyList<string> ProfileNames { get; }

    public static MainWindowViewModel LoadFromLegacyStore()
    {
        var storePath = Environment.GetEnvironmentVariable("BEEFORGE_PROFILE_STORE");
        if (string.IsNullOrWhiteSpace(storePath))
            storePath = System.IO.Path.Combine(AppContext.BaseDirectory, "config", "profiles.json");
        if (!File.Exists(storePath))
            return new MainWindowViewModel("Профили не найдены. Старый BeeForge не изменён.",
                "—", "—", 0, Array.Empty<string>());
        try
        {
            var catalog = LegacyProfileCatalog.Load(storePath);
            return new MainWindowViewModel("Профили считаны без изменений",
                catalog.ActiveProfile?.Name ?? "Не выбран", catalog.ActiveProfile?.ConnectionMode ?? "—",
                catalog.Profiles.Count, catalog.Profiles.Select(p => p.Name).ToArray());
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidDataException)
        {
            return new MainWindowViewModel("Не удалось прочитать профили. Старая консоль остаётся доступна.",
                "—", "—", 0, Array.Empty<string>());
        }
    }
}
