using System.ComponentModel;
using System.Runtime.CompilerServices;
using Avalonia.Threading;
using BeeForge.Next.Core.Inference;
using BeeForge.Next.Core.Profiles;
using BeeForge.Next.Core.Workspace;

namespace BeeForge.Next.App.ViewModels;

public sealed class MainWindowViewModel : INotifyPropertyChanged
{
    private readonly string? _storePath;
    private readonly string? _launchPlanScript;
    private readonly LegacyRuntimeController? _runtimeController;
    private readonly LegacyLogTailReader? _logReader;
    private readonly string? _openCodeConfigPath;
    private CancellationTokenSource? _selectionCancellation;
    private ProfileOption? _selectedProfile;
    private string _commandPreview = "Выберите профиль для просмотра аргументов запуска.";
    private string _runtimeStatusText = "Нажмите «Проверить состояние», чтобы получить данные из рабочего BeeForge.";
    private string _modelMetadataText = "Выберите локальный профиль для просмотра GGUF.";
    private string _runtimeDetailsText = "Подробные показатели появятся после проверки состояния.";
    private string _logText = "Выберите журнал для просмотра последних записей.";
    private string _teamText = "Нажмите «Обновить команду» для просмотра действующих агентов OpenCode.";
    private string _activeProfile = "Не выбран";
    private string _mode = "—";
    private bool _isRuntimeBusy;
    private bool _leaseKnown;
    private bool _isLeased;

    private MainWindowViewModel(string status, LegacyProfileCatalog? catalog,
        string? storePath, string? launchPlanScript, string? root)
    {
        Status = status;
        _storePath = storePath;
        _openCodeConfigPath = catalog?.OpenCodeConfigPath;
        _launchPlanScript = launchPlanScript;
        var runtimeScript = launchPlanScript is null ? null : Path.Combine(Path.GetDirectoryName(launchPlanScript)!,
            "Invoke-BeeForgeNextRuntime.ps1");
        if (storePath is not null && runtimeScript is not null && File.Exists(runtimeScript))
            _runtimeController = new LegacyRuntimeController(runtimeScript, storePath);
        if (root is not null) _logReader = new LegacyLogTailReader(root);
        ProfileNames = catalog?.Profiles.Select(p => new ProfileOption(p.Id, p.Name, p.ConnectionMode, p.ModelPath)).ToArray()
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
            _ = UpdateModelMetadataAsync(value, _selectionCancellation.Token);
        }
    }

    public string CommandPreview
    {
        get => _commandPreview;
        private set { _commandPreview = value; OnPropertyChanged(); }
    }

    public string ModelMetadataText
    {
        get => _modelMetadataText;
        private set { _modelMetadataText = value; OnPropertyChanged(); }
    }

    public string RuntimeDetailsText
    {
        get => _runtimeDetailsText;
        private set { _runtimeDetailsText = value; OnPropertyChanged(); }
    }

    public string LogText
    {
        get => _logText;
        private set { _logText = value; OnPropertyChanged(); }
    }

    public string TeamText
    {
        get => _teamText;
        private set { _teamText = value; OnPropertyChanged(); }
    }

    public async Task RefreshTeamAsync()
    {
        if (string.IsNullOrWhiteSpace(_openCodeConfigPath) || !File.Exists(_openCodeConfigPath))
        {
            TeamText = "Конфигурация OpenCode не найдена. Проверьте путь в рабочей консоли.";
            return;
        }
        try
        {
            var snapshot = await Task.Run(() => OpenCodeTeamSnapshotReader.Read(_openCodeConfigPath));
            var agentLines = snapshot.Agents.Select(agent =>
                $"{(agent.Disabled ? "○" : "●")} {agent.Id} · {agent.Mode} · {agent.Model}");
            var mcpLines = snapshot.McpServers.Select(server =>
                $"{(server.Enabled ? "●" : "○")} {server.Id}");
            TeamText = $"Модель: {snapshot.PrimaryModel}" + Environment.NewLine +
                $"Агенты ({snapshot.Agents.Count}):" + Environment.NewLine +
                string.Join(Environment.NewLine, agentLines) + Environment.NewLine + Environment.NewLine +
                $"OpenCode MCP ({snapshot.McpServers.Count}):" + Environment.NewLine +
                string.Join(Environment.NewLine, mcpLines) + Environment.NewLine + Environment.NewLine +
                "Промпты, команды MCP и ключи не отображаются.";
        }
        catch (Exception) { TeamText = "Не удалось прочитать конфигурацию OpenCode. Она не изменена."; }
    }

    public async Task RefreshLogAsync(string kind)
    {
        if (_logReader is null) { LogText = "Каталог журналов BeeForge не найден."; return; }
        try { LogText = await Task.Run(() => _logReader.Read(kind)); }
        catch (Exception) { LogText = "Не удалось прочитать журнал. Работа модели не затронута."; }
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
            RuntimeDetailsText = DescribeResources(status);
        }
        catch (Exception)
        {
            _leaseKnown = false;
            OnPropertyChanged(nameof(CanControlLocal));
            RuntimeStatusText = "Не удалось прочитать состояние. Проверьте старую консоль и её журналы.";
            RuntimeDetailsText = "Показатели недоступны.";
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
            RuntimeDetailsText = DescribeResources(status);
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

    private static string DescribeResources(LegacyRuntimeStatus status)
    {
        if (status.Remote) return "Ресурсы удалённого ПК здесь не измеряются.";
        var vram = status.VramUsedMiB is null || status.VramTotalMiB is null
            ? "VRAM: —" : $"VRAM: {status.VramUsedMiB / 1024.0:0.0} / {status.VramTotalMiB / 1024.0:0.0} GiB";
        var ram = status.RamUsedGiB is null || status.RamTotalGiB is null
            ? "RAM: —" : $"RAM: {status.RamUsedGiB:0.0} / {status.RamTotalGiB:0.0} GiB";
        return $"{vram} · {ram} · время работы: {(string.IsNullOrWhiteSpace(status.Uptime) ? "—" : status.Uptime)}";
    }

    public static MainWindowViewModel LoadFromLegacyStore()
    {
        var root = FindBeeForgeRoot();
        var storePath = Environment.GetEnvironmentVariable("BEEFORGE_PROFILE_STORE")
            ?? (root is null ? null : Path.Combine(root, "config", "profiles.json"));
        if (storePath is null || !File.Exists(storePath))
            return new MainWindowViewModel("Профили не найдены. Старая консоль не изменена.",
                null, null, null, root);
        try
        {
            var catalog = LegacyProfileCatalog.Load(storePath);
            var script = root is null ? null : Path.Combine(root, "scripts", "Get-BeeForgeNextLaunchPlan.ps1");
            return new MainWindowViewModel("Профили считаны без изменений", catalog, storePath, script, root);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or
            System.Text.Json.JsonException or InvalidDataException)
        {
            return new MainWindowViewModel("Не удалось прочитать профили. Старая консоль доступна.",
                null, null, null, root);
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

    private async Task UpdateModelMetadataAsync(ProfileOption? selected, CancellationToken cancellationToken)
    {
        if (selected is null || selected.Mode == "RemoteClient")
        {
            ModelMetadataText = "Для удалённой модели метаданные хранятся на основном ПК.";
            return;
        }
        if (string.IsNullOrWhiteSpace(selected.ModelPath) || !File.Exists(selected.ModelPath))
        {
            ModelMetadataText = "Файл GGUF этого профиля не найден на данном ПК.";
            return;
        }
        ModelMetadataText = "Читаю заголовок GGUF без загрузки весов…";
        try
        {
            var tensorSummary = await Task.Run(() => GgufMetadataReader.ReadTensorTable(selected.ModelPath), cancellationToken);
            if (cancellationToken.IsCancellationRequested) return;
            var metadata = tensorSummary.Metadata;
            var fields = metadata.Values.Select(pair => $"{pair.Key}: {pair.Value}");
            var tensorTypes = string.Join(", ", tensorSummary.TypeCounts.OrderByDescending(pair => pair.Value)
                .Select(pair => $"{GgmlTensorTypes.Name(pair.Key)} {pair.Value}"));
            var display = $"Файл: {Path.GetFileName(selected.ModelPath)} · GGUF v{metadata.Version} · " +
                $"тензоров: {metadata.TensorCount} · размер: {metadata.FileSizeBytes / 1073741824.0:0.00} GiB" +
                Environment.NewLine + $"Типы тензоров: {tensorTypes}" +
                Environment.NewLine + string.Join(Environment.NewLine, fields);
            Dispatcher.UIThread.Post(() => { if (!cancellationToken.IsCancellationRequested) ModelMetadataText = display; });
        }
        catch (OperationCanceledException) { }
        catch (Exception)
        {
            if (cancellationToken.IsCancellationRequested) return;
            Dispatcher.UIThread.Post(() =>
            {
                if (!cancellationToken.IsCancellationRequested)
                    ModelMetadataText = "Не удалось прочитать заголовок GGUF. Профиль и файл модели не изменены.";
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

public sealed record ProfileOption(string Id, string Name, string Mode, string ModelPath)
{
    public override string ToString() => $"{Name} · {Mode}";
}
