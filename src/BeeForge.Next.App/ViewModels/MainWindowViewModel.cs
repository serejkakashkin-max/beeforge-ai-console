using System.ComponentModel;
using System.Runtime.CompilerServices;
using Avalonia.Threading;
using BeeForge.Next.Core.Inference;
using BeeForge.Next.Core.Profiles;

namespace BeeForge.Next.App.ViewModels;

public sealed class MainWindowViewModel : INotifyPropertyChanged
{
    private readonly string? _storePath;
    private readonly string? _launchPlanScript;
    private CancellationTokenSource? _selectionCancellation;
    private ProfileOption? _selectedProfile;
    private string _commandPreview = "Выберите профиль для просмотра аргументов запуска.";

    private MainWindowViewModel(string status, LegacyProfileCatalog? catalog,
        string? storePath, string? launchPlanScript)
    {
        Status = status;
        _storePath = storePath;
        _launchPlanScript = launchPlanScript;
        ProfileNames = catalog?.Profiles.Select(p => new ProfileOption(p.Id, p.Name, p.ConnectionMode)).ToArray()
            ?? Array.Empty<ProfileOption>();
        ActiveProfile = catalog?.ActiveProfile?.Name ?? "Не выбран";
        Mode = catalog?.ActiveProfile?.ConnectionMode ?? "—";
        ProfileCount = ProfileNames.Count;
        SelectedProfile = ProfileNames.FirstOrDefault(p => p.Id == catalog?.ActiveProfileId)
            ?? ProfileNames.FirstOrDefault();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public string Status { get; }
    public string ActiveProfile { get; }
    public string Mode { get; }
    public int ProfileCount { get; }
    public IReadOnlyList<ProfileOption> ProfileNames { get; }

    public ProfileOption? SelectedProfile
    {
        get => _selectedProfile;
        set
        {
            if (_selectedProfile == value) return;
            _selectedProfile = value;
            OnPropertyChanged();
            _selectionCancellation?.Cancel();
            _selectionCancellation?.Dispose();
            _selectionCancellation = new CancellationTokenSource();
            _ = UpdateCommandPreviewAsync(value, _selectionCancellation.Token);
        }
    }

    public string CommandPreview
    {
        get => _commandPreview;
        private set { _commandPreview = value; OnPropertyChanged(); }
    }

    public static MainWindowViewModel LoadFromLegacyStore()
    {
        var root = FindBeeForgeRoot();
        var storePath = Environment.GetEnvironmentVariable("BEEFORGE_PROFILE_STORE")
            ?? (root is null ? null : Path.Combine(root, "config", "profiles.json"));
        if (storePath is null || !File.Exists(storePath))
            return new MainWindowViewModel("Профили не найдены. Старая консоль не изменена.",
                null, null, null);
        try
        {
            var catalog = LegacyProfileCatalog.Load(storePath);
            var script = root is null ? null : Path.Combine(root, "scripts", "Get-BeeForgeNextLaunchPlan.ps1");
            return new MainWindowViewModel("Профили считаны без изменений", catalog, storePath, script);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or
            System.Text.Json.JsonException or InvalidDataException)
        {
            return new MainWindowViewModel("Не удалось прочитать профили. Старая консоль доступна.",
                null, null, null);
        }
    }

    private async Task UpdateCommandPreviewAsync(ProfileOption? selected, CancellationToken cancellationToken)
    {
        if (selected is null) { CommandPreview = "Выберите профиль."; return; }
        if (selected.Mode == "RemoteClient")
        {
            CommandPreview = "Удалённый профиль: локальный сервер не запускается.";
            return;
        }
        if (_storePath is null || _launchPlanScript is null || !File.Exists(_launchPlanScript))
        {
            CommandPreview = "Генератор аргументов старого BeeForge не найден.";
            return;
        }
        CommandPreview = "Читаю план запуска из существующего BeeForge…";
        try
        {
            var plan = await LegacyLaunchPlanReader.ReadAsync(_launchPlanScript, _storePath,
                selected.Id, cancellationToken);
            if (cancellationToken.IsCancellationRequested) return;
            var preview = plan.Mode == "RemoteClient"
                ? "Удалённый профиль: локальный сервер не запускается."
                : plan.ServerPath + Environment.NewLine +
                  string.Join(Environment.NewLine, plan.Arguments.Select((arg, index) => $"{index:00}  {arg}"));
            Dispatcher.UIThread.Post(() => { if (!cancellationToken.IsCancellationRequested) CommandPreview = preview; });
        }
        catch (OperationCanceledException) { }
        catch (Exception)
        {
            if (cancellationToken.IsCancellationRequested) return;
            Dispatcher.UIThread.Post(() =>
            {
                if (!cancellationToken.IsCancellationRequested)
                    CommandPreview = "Не удалось получить план запуска. Рабочий профиль не изменён.";
            });
        }
    }

    private static string? FindBeeForgeRoot()
    {
        var configured = Environment.GetEnvironmentVariable("BEEFORGE_ROOT");
        if (!string.IsNullOrWhiteSpace(configured) &&
            File.Exists(Path.Combine(configured, "scripts", "BeeLlamaManager.Core.psm1")))
            return Path.GetFullPath(configured);
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null;
             directory = directory.Parent)
            if (File.Exists(Path.Combine(directory.FullName, "scripts", "BeeLlamaManager.Core.psm1")))
                return directory.FullName;
        return null;
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed record ProfileOption(string Id, string Name, string Mode)
{
    public override string ToString() => $"{Name} · {Mode}";
}
