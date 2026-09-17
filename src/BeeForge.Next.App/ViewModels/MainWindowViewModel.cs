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
    private readonly LegacyRuntimeController? _runtimeController;
    private CancellationTokenSource? _selectionCancellation;
    private ProfileOption? _selectedProfile;
    private string _commandPreview = "Выберите профиль для просмотра аргументов запуска.";
    private string _runtimeStatusText = "Нажмите «Проверить состояние», чтобы получить данные из рабочего BeeForge.";
    private string _activeProfile = "Не выбран";
    private string _mode = "—";
    private bool _isRuntimeBusy;
    private bool _leaseKnown;
    private bool _isLeased;

    private MainWindowViewModel(string status, LegacyProfileCatalog? catalog,
        string? storePath, string? launchPlanScript)
    {
        Status = status;
        _storePath = storePath;
        _launchPlanScript = launchPlanScript;
        var runtimeScript = launchPlanScript is null ? null : Path.Combine(Path.GetDirectoryName(launchPlanScript)!,
            "Invoke-BeeForgeNextRuntime.ps1");
        if (storePath is not null && runtimeScript is not null && File.Exists(runtimeScript))
            _runtimeController = new LegacyRuntimeController(runtimeScript, storePath);
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
    public string ActiveProfile
    {
        get => _activeProfile;
        private set { _activeProfile = value; OnPropertyChanged(); }
    }
    public string Mode
    {
        get => _mode;
        private set { _mode = value; OnPropertyChanged(); }
    }
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
            OnPropertyChanged(nameof(CanControlLocal));
            OnPropertyChanged(nameof(CanConnectRemote));
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

    public string RuntimeStatusText
    {
        get => _runtimeStatusText;
        private set { _runtimeStatusText = value; OnPropertyChanged(); }
    }

    public bool IsRuntimeBusy
    {
        get => _isRuntimeBusy;
        private set
        {
            _isRuntimeBusy = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanControlLocal));
            OnPropertyChanged(nameof(CanConnectRemote));
            OnPropertyChanged(nameof(CanRefreshRuntime));
        }
    }

    public bool CanControlLocal => !IsRuntimeBusy && _leaseKnown && !_isLeased &&
        SelectedProfile?.Mode == "LocalHost" &&
        _runtimeController is not null;
    public bool CanConnectRemote => !IsRuntimeBusy && SelectedProfile?.Mode == "RemoteClient" &&
        _runtimeController is not null;
    public bool CanRefreshRuntime => !IsRuntimeBusy && _runtimeController is not null;

    public async Task RefreshRuntimeStatusAsync()
    {
        if (_runtimeController is null || IsRuntimeBusy) return;
        IsRuntimeBusy = true;
        try
        {
            var status = await _runtimeController.GetStatusAsync();
            _leaseKnown = true;
            _isLeased = status.Leased;
            OnPropertyChanged(nameof(CanControlLocal));
            RuntimeStatusText = status.Leased
                ? "Модель передана ноутбуку. Выключите удалённый доступ в рабочей консоли, прежде чем управлять ею здесь."
                : DescribeRuntime(status);
        }
        catch (Exception)
        {
            _leaseKnown = false;
            OnPropertyChanged(nameof(CanControlLocal));
            RuntimeStatusText = "Не удалось прочитать состояние. Проверьте старую консоль и её журналы.";
        }
        finally { IsRuntimeBusy = false; }
    }

    public async Task StartSelectedAsync()
    {
        if (_runtimeController is null || !CanControlLocal || SelectedProfile is null) return;
        IsRuntimeBusy = true;
        RuntimeStatusText = "Проверка профиля и запуск через рабочий BeeForge…";
        try
        {
            var status = await _runtimeController.StartAsync(SelectedProfile.Id);
            RuntimeStatusText = DescribeRuntime(status);
            if (status.Ready)
            {
                ActiveProfile = SelectedProfile.Name;
                Mode = SelectedProfile.Mode;
            }
        }
        catch (Exception)
        {
            RuntimeStatusText = "Запуск не завершился. Проверьте журналы в старой консоли; не запускайте повторно до проверки состояния.";
        }
        finally { IsRuntimeBusy = false; }
    }

    public async Task StopSelectedAsync()
    {
        if (_runtimeController is null || !CanControlLocal || SelectedProfile is null) return;
        IsRuntimeBusy = true;
        try
        {
            var message = await _runtimeController.StopAsync(SelectedProfile.Id);
            RuntimeStatusText = message;
        }
        catch (Exception)
        {
            RuntimeStatusText = "Остановка не подтверждена. Проверьте состояние в старой консоли.";
        }
        finally { IsRuntimeBusy = false; }
    }

    public async Task ConnectSelectedRemoteAsync()
    {
        if (_runtimeController is null || !CanConnectRemote || SelectedProfile is null) return;
        var selected = SelectedProfile;
        IsRuntimeBusy = true;
        RuntimeStatusText = "Проверяю удалённую модель через рабочий BeeForge…";
        try
        {
            var message = await _runtimeController.ConnectRemoteAsync(selected.Id);
            ActiveProfile = selected.Name;
            Mode = selected.Mode;
            RuntimeStatusText = $"Удалённый профиль подключён: {message}";
        }
        catch (Exception)
        {
            RuntimeStatusText = "Удалённый профиль не подключён. Проверьте Tailscale и модель на основном ПК. OpenCode не переключён.";
        }
        finally { IsRuntimeBusy = false; }
    }

    private static string DescribeRuntime(LegacyRuntimeStatus status)
    {
        if (status.Remote) return $"Удалённый профиль: {(status.Ready ? "READY" : "OFFLINE")} · {status.Message}";
        if (!status.Running) return "Локальная модель остановлена.";
        var state = status.Ready ? "READY" : "Загружается";
        var speed = status.PromptTokensPerSecond is null && status.DecodeTokensPerSecond is null
            ? "" : $" · PP {status.PromptTokensPerSecond?.ToString("0.0") ?? "—"} / TG {status.DecodeTokensPerSecond?.ToString("0.0") ?? "—"} tok/s";
        return $"{state} · {status.Profile} · PID {status.Pid?.ToString() ?? "—"}{speed}";
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
