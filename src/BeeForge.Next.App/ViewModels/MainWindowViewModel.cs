using System.ComponentModel;
using System.Collections.ObjectModel;
using System.Runtime.CompilerServices;
using Avalonia.Threading;
using BeeForge.Next.Core.Benchmarking;
using BeeForge.Next.Core.Inference;
using BeeForge.Next.Core.Profiles;
using BeeForge.Next.Core.Workspace;

namespace BeeForge.Next.App.ViewModels;

public sealed class MainWindowViewModel : INotifyPropertyChanged
{
    private readonly string? _storePath;
    private readonly string? _launchPlanScript;
    private readonly LegacyRuntimeController? _runtimeController;
    private readonly StandardBenchmarkRunner? _benchmarkRunner;
    private readonly BenchmarkRunStore? _benchmarkStore;
    private readonly IsolatedAutoTuner? _autoTuner;
    private AutoTuneResult? _tuneResult;
    private string? _tuneFingerprint;
    private CancellationTokenSource? _benchmarkCancellation;
    private readonly LegacyLogTailReader? _logReader;
    private readonly string? _openCodeConfigPath;
    private readonly LegacyServiceController? _services;
    private readonly RuntimeCatalog? _runtimeCatalog;
    private readonly RuntimeInstaller? _runtimeInstaller;
    private readonly OfflineHelpService? _help;
    private readonly HuggingFaceService _hf = new();
    private bool _servicesBusy;
    private string _serviceText = "Выберите действие. Состояние читается из существующего BeeForge.";
    private string _runtimeCatalogText = "Установленные runtime ещё не проверены.";
    public string RuntimeCatalogText { get => _runtimeCatalogText; private set { _runtimeCatalogText = value; OnPropertyChanged(); } }
    private string _helpText = "Выберите раздел локальной справки.";
    public string HelpText { get => _helpText; private set { _helpText = value; OnPropertyChanged(); } }
    public bool CanUseServices => !_servicesBusy && !IsBenchmarkBusy && !IsRuntimeBusy && _services is not null;
    public string ServiceText { get => _serviceText; private set { _serviceText = value; OnPropertyChanged(); } }

    public async Task RunServiceAsync(ServiceAction action)
    {
        if (!CanUseServices) return;
        _servicesBusy = true; NotifyActionAvailability();
        ServiceText = "Выполняется…";
        try
        {
            var result = await _services!.InvokeAsync(action, SelectedProfile?.Id);
            ServiceText = System.Text.Json.JsonSerializer.Serialize(result, new System.Text.Json.JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
            if (action is ServiceAction.RemoteEnable or ServiceAction.RemoteDisable) await RefreshRuntimeStatusAsync();
        }
        catch (Exception ex) { ServiceText = ex.Message; }
        finally { _servicesBusy = false; NotifyActionAvailability(); }
    }

    private void NotifyActionAvailability()
    {
        foreach (var name in new[] { nameof(CanUseServices), nameof(CanControlLocal), nameof(CanConnectRemote),
            nameof(CanRunBenchmark), nameof(CanAutoTune) }) OnPropertyChanged(name);
    }
    private CancellationTokenSource? _selectionCancellation;
    private ProfileOption? _selectedProfile;
    private string _commandPreview = "Выберите профиль для просмотра аргументов запуска.";
    private string _runtimeStatusText = "Нажмите «Проверить состояние», чтобы получить данные из рабочего BeeForge.";
    private string _modelMetadataText = "Выберите локальный профиль для просмотра GGUF.";
    private string _runtimeDetailsText = "Подробные показатели появятся после проверки состояния.";
    private string _logText = "Выберите журнал для просмотра последних записей.";
    private string _teamText = "Нажмите «Обновить команду» для просмотра действующих агентов OpenCode.";
    private string _benchmarkStatusText = "Проверьте состояние теста скорости.";
    private string _benchmarkHistoryText = "Истории замеров пока нет.";
    private IReadOnlyList<BenchmarkRunOption> _benchmarkRunOptions = Array.Empty<BenchmarkRunOption>();
    private string _activeProfileId = "";
    private bool _runtimeReady;
    private bool _runtimeRunning;
    private bool _isBenchmarkBusy;
    private string _activeProfile = "Не выбран";
    private string _mode = "—";
    private bool _isRuntimeBusy;
    private bool _leaseKnown;
    private bool _isLeased;
    private bool _hfBusy;
    private string _hfQuery = "Qwen GGUF";
    private HfRepo? _selectedHfRepo;
    private HfFile? _selectedHfFile;
    private string _hfStatus = "Найдите GGUF-модель на Hugging Face.";
    public ObservableCollection<HfRepo> HfRepos { get; } = new();
    public ObservableCollection<HfFile> HfFiles { get; } = new();
    public string HfQuery { get => _hfQuery; set { _hfQuery = value; OnPropertyChanged(); } }
    public HfRepo? SelectedHfRepo { get => _selectedHfRepo; set { _selectedHfRepo = value; OnPropertyChanged(); } }
    public HfFile? SelectedHfFile { get => _selectedHfFile; set { _selectedHfFile = value; OnPropertyChanged(); } }
    public string HfStatus { get => _hfStatus; private set { _hfStatus = value; OnPropertyChanged(); } }
    public bool CanUseHf => !_hfBusy;

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
        if (root is not null)
        {
            if (storePath is not null) _services = new LegacyServiceController(Path.Combine(root, "scripts", "Invoke-BeeForgeNextServices.ps1"), storePath);
            _benchmarkStore = new BenchmarkRunStore(root);
            _benchmarkRunner = new StandardBenchmarkRunner(new HttpBenchmarkProbe(), _benchmarkStore);
            _runtimeCatalog = new RuntimeCatalog(root);
            _runtimeInstaller = new RuntimeInstaller(root);
            _help = new OfflineHelpService(root);
        }
        if (_runtimeController is not null && launchPlanScript is not null)
            _autoTuner = new IsolatedAutoTuner(launchPlanScript, _runtimeController);
        if (root is not null) _logReader = new LegacyLogTailReader(root);
        ProfileNames = catalog?.Profiles.Select(p => new ProfileOption(p.Id, p.Name, p.ConnectionMode, p.ModelPath)).ToArray()
            ?? Array.Empty<ProfileOption>();
        ActiveProfile = catalog?.ActiveProfile?.Name ?? "Не выбран";
        _activeProfileId = catalog?.ActiveProfileId ?? "";
        Mode = catalog?.ActiveProfile?.ConnectionMode ?? "—";
        ProfileCount = ProfileNames.Count;
        SelectedProfile = ProfileNames.FirstOrDefault(p => p.Id == catalog?.ActiveProfileId)
            ?? ProfileNames.FirstOrDefault();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public async Task SearchHfAsync()
    {
        if (_hfBusy) return;
        _hfBusy = true; OnPropertyChanged(nameof(CanUseHf)); HfStatus = "Поиск…";
        try
        {
            var results = await _hf.SearchAsync(HfQuery);
            HfRepos.Clear(); foreach (var item in results) HfRepos.Add(item);
            HfFiles.Clear(); SelectedHfRepo = HfRepos.FirstOrDefault(); SelectedHfFile = null;
            HfStatus = results.Count == 0 ? "GGUF-репозитории не найдены." : $"Найдено: {results.Count}. Выберите репозиторий и загрузите список файлов.";
        }
        catch (Exception) { HfStatus = "Поиск Hugging Face не удался. Проверьте сеть или доступ к репозиторию."; }
        finally { _hfBusy = false; OnPropertyChanged(nameof(CanUseHf)); }
    }

    public async Task LoadHfFilesAsync()
    {
        if (_hfBusy || SelectedHfRepo is null) return;
        _hfBusy = true; OnPropertyChanged(nameof(CanUseHf)); HfStatus = "Читаю список GGUF…";
        try
        {
            var files = await _hf.ListGgufAsync(SelectedHfRepo.Id);
            HfFiles.Clear(); foreach (var item in files) HfFiles.Add(item);
            SelectedHfFile = HfFiles.FirstOrDefault(); HfStatus = $"GGUF-файлов: {files.Count}.";
        }
        catch (Exception) { HfStatus = "Не удалось получить список файлов. Для gated-модели задайте HF_TOKEN локально."; }
        finally { _hfBusy = false; OnPropertyChanged(nameof(CanUseHf)); }
    }

    public async Task DownloadHfAsync(string directory)
    {
        if (_hfBusy || SelectedHfRepo is null || SelectedHfFile is null) return;
        _hfBusy = true; OnPropertyChanged(nameof(CanUseHf));
        var progress = new Progress<HfDownloadProgress>(p => HfStatus = $"Загрузка {SelectedHfFile.Path}: {p.Percent:0.0}% · {p.BytesDone / 1048576.0:0} MiB");
        try
        {
            var path = await _hf.DownloadAsync(SelectedHfRepo.Id, SelectedHfFile, directory, progress);
            HfStatus = "Готово: " + path;
        }
        catch (OperationCanceledException) { HfStatus = "Загрузка остановлена; .part сохранён для продолжения."; }
        catch (Exception) { HfStatus = "Загрузка не завершилась; частичный файл сохранён для продолжения."; }
        finally { _hfBusy = false; OnPropertyChanged(nameof(CanUseHf)); }
    }

    public void ShowHelp(string topic)
    {
        try { HelpText = _help?.Read(topic) ?? "Локальная справка недоступна."; }
        catch (Exception) { HelpText = "Не удалось открыть локальную справку."; }
    }

    public void RefreshRuntimeCatalog()
    {
        if (_runtimeCatalog is null) { RuntimeCatalogText = "Каталог runtime недоступен."; return; }
        var items = _runtimeCatalog.ListInstalled();
        RuntimeCatalogText = items.Count == 0 ? "Управляемые runtime не найдены." : string.Join(Environment.NewLine,
            items.Select(x => $"{x.Provider} · {x.Version} · {x.Detail}{Environment.NewLine}{x.ServerPath}"));
    }

    public async Task InstallRecommendedRuntimeAsync()
    {
        if (_runtimeInstaller is null || IsRuntimeBusy) return;
        IsRuntimeBusy = true;
        RuntimeCatalogText = "Устанавливаю BeeLlama v0.4.6 CUDA 13.3 с проверкой SHA-256…";
        try
        {
            await _runtimeInstaller.InstallBeeLlamaAsync();
            RefreshRuntimeCatalog();
        }
        catch (Exception) { RuntimeCatalogText = "Установка не завершилась. Рабочие профили не переключались."; }
        finally { IsRuntimeBusy = false; }
    }
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
    public int ProfileCount { get; private set; }
    public IReadOnlyList<ProfileOption> ProfileNames { get; private set; }
    private string _profileMessage = "Выберите профиль для редактирования или создайте новый.";
    public string ProfileMessage { get => _profileMessage; private set { _profileMessage = value; OnPropertyChanged(); } }

    public LegacyProfileCatalog ReadProfileCatalog() => LegacyProfileCatalog.Load(
        _storePath ?? throw new IOException("Хранилище профилей не найдено."));

    public void ReloadProfiles(string? selectedId = null)
    {
        try
        {
            var catalog = ReadProfileCatalog();
            var selected = selectedId ?? SelectedProfile?.Id;
            ProfileNames = catalog.Profiles.Select(p => new ProfileOption(p.Id, p.Name, p.ConnectionMode, p.ModelPath)).ToArray();
            ProfileCount = ProfileNames.Count;
            ActiveProfile = catalog.ActiveProfile?.Name ?? "Не выбран";
            _activeProfileId = catalog.ActiveProfileId;
            OnPropertyChanged(nameof(ProfileNames)); OnPropertyChanged(nameof(ProfileCount));
            SelectedProfile = ProfileNames.FirstOrDefault(p => p.Id == selected) ?? ProfileNames.FirstOrDefault();
            ProfileMessage = "Профили обновлены.";
        }
        catch (Exception ex) { ProfileMessage = ex.Message; }
    }

    public void SaveProfile(LegacyProfileCatalog snapshot, string id, string json)
    {
        new ProfileStoreEditor(snapshot.Path).Save(snapshot.OriginalJson, id, json);
        ReloadProfiles(id);
        ProfileMessage = "Профиль сохранён. Резервная копия создана; параметры вступят в силу при следующем запуске модели.";
    }

    public void AddProfile(LegacyProfileCatalog snapshot, string json, bool copyName)
    {
        var id = new ProfileStoreEditor(snapshot.Path).Add(snapshot.OriginalJson, json, copyName);
        ReloadProfiles(id);
        ProfileMessage = "Новый профиль сохранён.";
    }

    public void DeleteProfile(LegacyProfileCatalog snapshot, string id)
    {
        var next = new ProfileStoreEditor(snapshot.Path).Delete(snapshot.OriginalJson, id);
        ReloadProfiles(next);
        ProfileMessage = "Профиль удалён. Предыдущее состояние доступно в резервной копии.";
    }

    public void SetProfileMessage(string message) => ProfileMessage = message;

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
            OnPropertyChanged(nameof(CanRunBenchmark));
            OnPropertyChanged(nameof(CanAutoTune));
            OnPropertyChanged(nameof(CanSaveTune));
            _tuneResult = null;
            _tuneFingerprint = null;
            _selectionCancellation?.Cancel();
            _selectionCancellation?.Dispose();
            _selectionCancellation = new CancellationTokenSource();
            _ = UpdateCommandPreviewAsync(value, _selectionCancellation.Token);
            _ = UpdateModelMetadataAsync(value, _selectionCancellation.Token);
            _ = RefreshBenchmarkStatusAsync();
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

    private string _benchmarkInputText = "4096";
    private string _benchmarkOutputText = "256";
    public string BenchmarkInputText
    {
        get => _benchmarkInputText;
        set { _benchmarkInputText = value; OnPropertyChanged(); }
    }
    public string BenchmarkOutputText
    {
        get => _benchmarkOutputText;
        set { _benchmarkOutputText = value; OnPropertyChanged(); }
    }
    public void SetBenchmarkPreset(string preset)
    {
        (BenchmarkInputText, BenchmarkOutputText) = preset switch
        {
            "short" => ("512", "128"),
            "long" => ("32768", "256"),
            _ => ("4096", "256")
        };
    }
    public string BenchmarkTimeoutText { get; set; } = "900";
    public string BenchmarkRepeatsText { get; set; } = "3";
    public IReadOnlyList<string> OptimizationObjectives { get; } =
        new[] { "Баланс PP/TG", "Максимум PP", "Максимум TG" };
    public string SelectedOptimizationObjective { get; set; } = "Баланс PP/TG";
    public string BenchmarkHistoryText
    {
        get => _benchmarkHistoryText;
        private set { _benchmarkHistoryText = value; OnPropertyChanged(); }
    }
    public IReadOnlyList<BenchmarkRunOption> BenchmarkRunOptions
    {
        get => _benchmarkRunOptions;
        private set { _benchmarkRunOptions = value; OnPropertyChanged(); }
    }
    public string BenchmarkStatusText
    {
        get => _benchmarkStatusText;
        private set { _benchmarkStatusText = value; OnPropertyChanged(); }
    }
    public bool IsBenchmarkBusy
    {
        get => _isBenchmarkBusy;
        private set
        {
            _isBenchmarkBusy = value;
            NotifyActionAvailability();
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanRunBenchmark));
            OnPropertyChanged(nameof(CanStopBenchmark));
            OnPropertyChanged(nameof(CanRefreshBenchmark));
            OnPropertyChanged(nameof(CanAutoTune));
            OnPropertyChanged(nameof(CanSaveTune));
        }
    }
    public bool CanRunBenchmark => !IsBenchmarkBusy && !IsRuntimeBusy && !_servicesBusy && _runtimeReady &&
        !_isLeased && SelectedProfile?.Id == _activeProfileId &&
        SelectedProfile?.Mode == "LocalHost" && _benchmarkRunner is not null;
    public bool CanStopBenchmark => IsBenchmarkBusy && _benchmarkCancellation is not null;
    public bool CanRefreshBenchmark => !IsBenchmarkBusy && _benchmarkStore is not null;
    public void SetBenchmarkMessage(string message) => BenchmarkStatusText = message;
    public bool CanAutoTune => !IsBenchmarkBusy && !IsRuntimeBusy && !_servicesBusy && _leaseKnown && !_isLeased &&
        !_runtimeRunning && SelectedProfile?.Mode == "LocalHost" && _autoTuner is not null;
    public bool CanSaveTune => !IsBenchmarkBusy && _tuneResult?.Suggested is not null &&
        SelectedProfile?.Mode == "LocalHost";

    public async Task RunAutoTuneAsync()
    {
        if (!CanAutoTune || _autoTuner is null || _storePath is null || SelectedProfile is null) return;
        LegacyProfile profile;
        try { profile = LegacyProfileCatalog.Load(_storePath).Profiles.Single(p => p.Id == SelectedProfile.Id); }
        catch (Exception) { BenchmarkStatusText = "Не удалось прочитать профиль для подбора."; return; }
        _tuneFingerprint = BenchmarkRunRequest.Fingerprint(profile.RawJson);
        _tuneResult = null;
        _benchmarkCancellation = new CancellationTokenSource();
        IsBenchmarkBusy = true;
        try
        {
            var progress = new Progress<string>(message => BenchmarkStatusText = message);
            var objective = SelectedOptimizationObjective switch
            {
                "Максимум PP" => OptimizationObjective.Prefill,
                "Максимум TG" => OptimizationObjective.Decode,
                _ => OptimizationObjective.Balanced
            };
            _tuneResult = await _autoTuner.RunAsync(profile.Id, profile.RawJson, objective,
                progress, _benchmarkCancellation.Token);
            var lines = _tuneResult.Trials.Select(t => t.Error is null
                ? $"{t.Candidate.Name}: PP {t.Prefill:0.0}, TG {t.Decode:0.0} tok/s"
                : $"{t.Candidate.Name}: ошибка {t.Error}");
            BenchmarkStatusText = string.Join(Environment.NewLine, lines) + Environment.NewLine +
                (_tuneResult.Suggested is null ? "Надёжного ускорения от 5% не найдено; профиль не изменён."
                : $"Предложение: {_tuneResult.Suggested.Name}, +{_tuneResult.ImprovementPercent:0.0}%. Можно создать отдельный профиль.");
        }
        catch (OperationCanceledException) { BenchmarkStatusText = "Автоподбор остановлен. Профиль не изменён."; }
        catch (Exception ex) { BenchmarkStatusText = $"Автоподбор не завершён: {ex.GetType().Name}. Профиль не изменён."; }
        finally { _benchmarkCancellation.Dispose(); _benchmarkCancellation = null; IsBenchmarkBusy = false; }
    }

    public void SaveAutoTuneProfile()
    {
        if (!CanSaveTune || _storePath is null || SelectedProfile is null ||
            _tuneResult?.Suggested is null || _tuneFingerprint is null) return;
        try
        {
            var id = AutoTuneProfileCreator.CreateCopy(_storePath, SelectedProfile.Id,
                _tuneFingerprint, _tuneResult.Suggested);
            BenchmarkStatusText = $"Создан отдельный профиль {id}. Исходный и активный профиль не изменены; перед использованием проверьте его в рабочей консоли.";
            _tuneResult = null;
            OnPropertyChanged(nameof(CanSaveTune));
        }
        catch (Exception ex) { BenchmarkStatusText = $"Не удалось создать профиль: {ex.GetType().Name}. Исходный профиль сохранён."; }
    }

    public Task RefreshBenchmarkStatusAsync()
    {
        if (_benchmarkStore is null || IsBenchmarkBusy) return Task.CompletedTask;
        try
        {
            var runs = _benchmarkStore.Load(limit: 50);
            BenchmarkRunOptions = runs.Select(run => new BenchmarkRunOption(run)).ToArray();
            var newest = runs.FirstOrDefault();
            var previous = newest is null ? null : runs.Skip(1).FirstOrDefault(run =>
                run.ModelAlias == newest.ModelAlias && run.PromptTokens == newest.PromptTokens &&
                run.OutputTokens == newest.OutputTokens);
            var comparison = newest is null || previous is null || previous.PrefillTokensPerSecond <= 0 ||
                previous.DecodeTokensPerSecond <= 0 ? "" :
                $"Последний замер относительно предыдущего с той же нагрузкой: PP {(newest.PrefillTokensPerSecond / previous.PrefillTokensPerSecond - 1) * 100:+0.0;-0.0;0.0}%, " +
                $"TG {(newest.DecodeTokensPerSecond / previous.DecodeTokensPerSecond - 1) * 100:+0.0;-0.0;0.0}%" +
                (newest.ProfileSha256 == previous.ProfileSha256 ? " (одинаковая конфигурация)" : " (профиль менялся)") +
                Environment.NewLine + Environment.NewLine;
            BenchmarkHistoryText = runs.Count == 0 ? "Истории замеров пока нет." :
                comparison + string.Join(Environment.NewLine, runs.Select(run =>
                    $"{run.CompletedAt.LocalDateTime:g} · {run.PromptTokens}/{run.OutputTokens} · " +
                    $"PP {run.PrefillTokensPerSecond:0.0} ±{run.PrefillStdDev:0.0} · " +
                    $"TG {run.DecodeTokensPerSecond:0.0} ±{run.DecodeStdDev:0.0} tok/s · " +
                    $"{run.Repeats} повторов · конфигурация {run.ProfileSha256[..8]}"));
        }
        catch (Exception)
        {
            BenchmarkRunOptions = Array.Empty<BenchmarkRunOption>();
            BenchmarkHistoryText = "Не удалось прочитать историю замеров.";
        }
        return Task.CompletedTask;
    }

    public async Task StartBenchmarkAsync()
    {
        if (_benchmarkRunner is null || !CanRunBenchmark || SelectedProfile is null || _storePath is null) return;
        if (!int.TryParse(BenchmarkInputText, out var input) || input < 256 || input > 200000 ||
            !int.TryParse(BenchmarkOutputText, out var output) || output < 16 || output > 4096 ||
            !int.TryParse(BenchmarkTimeoutText, out var timeout) || timeout < 30 || timeout > 3600 ||
            !int.TryParse(BenchmarkRepeatsText, out var repeats) || repeats < 2 || repeats > 10)
        {
            BenchmarkStatusText = "Проверьте значения: input 256–200000, output 16–4096, повторы 2–10, timeout 30–3600 с.";
            return;
        }
        LegacyProfileCatalog catalog;
        try { catalog = LegacyProfileCatalog.Load(_storePath); }
        catch (Exception) { BenchmarkStatusText = "Не удалось проверить активный профиль; тест не запущен."; return; }
        var profile = catalog.Profiles.FirstOrDefault(p => p.Id == SelectedProfile.Id);
        if (profile is null || catalog.ActiveProfileId != profile.Id || profile.ConnectionMode != "LocalHost")
        { BenchmarkStatusText = "Активный профиль изменился. Обновите состояние перед тестом."; return; }
        if (profile.Context > 0 && (long)input + output + 256 > profile.Context)
        { BenchmarkStatusText = $"Нагрузка превышает контекст профиля ({profile.Context} токенов)."; return; }
        int port;
        string? host;
        try
        {
            using var parsed = System.Text.Json.JsonDocument.Parse(profile.RawJson);
            port = parsed.RootElement.TryGetProperty("port", out var portValue) && portValue.TryGetInt32(out var p) ? p : 8080;
            host = parsed.RootElement.TryGetProperty("host", out var hostValue) ? hostValue.GetString() : "127.0.0.1";
        }
        catch (Exception) { BenchmarkStatusText = "Параметры адреса модели повреждены; тест не запущен."; return; }
        if (port is < 1 or > 65535 || host is not ("127.0.0.1" or "localhost" or "::1"))
        { BenchmarkStatusText = "Тест разрешён только для локального адреса модели."; return; }
        var endpoint = $"http://127.0.0.1:{port}/v1";
        var request = new BenchmarkRunRequest(profile.Id, profile.Name, profile.Alias, endpoint,
            BenchmarkRunRequest.Fingerprint(profile.RawJson), input, output, repeats, timeout);
        _benchmarkCancellation = new CancellationTokenSource();
        IsBenchmarkBusy = true;
        try
        {
            if (_runtimeController is null) throw new InvalidOperationException("Runtime unavailable.");
            var status = await _runtimeController.GetStatusAsync(_benchmarkCancellation.Token);
            if (!status.Ready || status.Leased || status.Remote)
                throw new InvalidOperationException("Runtime no longer available for local benchmark.");
            var progress = new Progress<BenchmarkProgress>(p =>
                BenchmarkStatusText = $"{p.Phase}: {p.Completed}/{p.Total}");
            var run = await _benchmarkRunner.RunAsync(request, progress, _benchmarkCancellation.Token);
            BenchmarkStatusText = $"Готово · PP {run.PrefillTokensPerSecond:0.0} ±{run.PrefillStdDev:0.0} · " +
                $"TG {run.DecodeTokensPerSecond:0.0} ±{run.DecodeStdDev:0.0} tok/s";
        }
        catch (OperationCanceledException) { BenchmarkStatusText = "Тест остановлен. Работа модели не затронута."; }
        catch (Exception ex) { BenchmarkStatusText = $"Тест не завершён: {ex.GetType().Name}. Проверьте активную модель и её совместимость с /completion."; }
        finally
        {
            _benchmarkCancellation.Dispose(); _benchmarkCancellation = null; IsBenchmarkBusy = false;
            await RefreshBenchmarkStatusAsync();
        }
    }

    public Task StopBenchmarkAsync()
    {
        _benchmarkCancellation?.Cancel();
        return Task.CompletedTask;
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
            NotifyActionAvailability();
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanControlLocal));
            OnPropertyChanged(nameof(CanConnectRemote));
            OnPropertyChanged(nameof(CanRefreshRuntime));
            OnPropertyChanged(nameof(CanRunBenchmark));
            OnPropertyChanged(nameof(CanAutoTune));
        }
    }

    public bool CanControlLocal => !IsRuntimeBusy && !IsBenchmarkBusy && !_servicesBusy && _leaseKnown && !_isLeased &&
        SelectedProfile?.Mode == "LocalHost" &&
        _runtimeController is not null;
    public bool CanConnectRemote => !IsRuntimeBusy && !IsBenchmarkBusy && !_servicesBusy && SelectedProfile?.Mode == "RemoteClient" &&
        _runtimeController is not null;
    public bool CanRefreshRuntime => !IsRuntimeBusy && _runtimeController is not null;

    public async Task RefreshRuntimeStatusAsync()
    {
        if (_runtimeController is null || IsRuntimeBusy) return;
        IsRuntimeBusy = true;
        try
        {
            var status = await _runtimeController.GetStatusAsync();
            _runtimeReady = status.Ready;
            _runtimeRunning = status.Running;
            OnPropertyChanged(nameof(CanRunBenchmark));
            OnPropertyChanged(nameof(CanAutoTune));
            _leaseKnown = true;
            _isLeased = status.Leased;
            OnPropertyChanged(nameof(CanControlLocal));
            OnPropertyChanged(nameof(CanRunBenchmark));
            OnPropertyChanged(nameof(CanAutoTune));
            RuntimeStatusText = status.Leased
                ? "Модель передана ноутбуку. Выключите удалённый доступ в рабочей консоли, прежде чем управлять ею здесь."
                : DescribeRuntime(status);
            RuntimeDetailsText = DescribeResources(status);
        }
        catch (Exception)
        {
            _leaseKnown = false;
            _runtimeReady = false;
            _runtimeRunning = false;
            OnPropertyChanged(nameof(CanControlLocal));
            OnPropertyChanged(nameof(CanRunBenchmark));
            OnPropertyChanged(nameof(CanAutoTune));
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
            _runtimeReady = status.Ready;
            _runtimeRunning = status.Running;
            _activeProfileId = SelectedProfile.Id;
            OnPropertyChanged(nameof(CanRunBenchmark));
            OnPropertyChanged(nameof(CanAutoTune));
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
            _runtimeReady = false;
            _runtimeRunning = false;
            OnPropertyChanged(nameof(CanRunBenchmark));
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
            _activeProfileId = selected.Id;
            _runtimeReady = true;
            OnPropertyChanged(nameof(CanRunBenchmark));
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
        var gpu = status.GpuUtilization is null ? "GPU: —" : $"GPU: {status.GpuUtilization}%";
        var temp = status.GpuTemperatureC is null ? "температура: —" : $"температура: {status.GpuTemperatureC} °C";
        var context = status.ContextTokens is null ? "контекст: —" : $"контекст: {status.ContextTokens:N0}";
        var slots = status.SlotsBusy is null || status.SlotsTotal is null ? "слоты: —" :
            $"слоты: {status.SlotsBusy}/{status.SlotsTotal} занято";
        var tokens = status.PromptTokens is null && status.DecodedTokens is null ? "" :
            $" · последний запрос: input {status.PromptTokens?.ToString("N0") ?? "—"}, output {status.DecodedTokens?.ToString("N0") ?? "—"}";
        return $"{vram} · {gpu} · {temp} · {ram} · {context} · {slots} · время работы: {(string.IsNullOrWhiteSpace(status.Uptime) ? "—" : status.Uptime)}{tokens}";
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
            var capability = await RuntimeCapabilityProbe.ProbeAsync(plan, cancellationToken);
            if (cancellationToken.IsCancellationRequested) return;
            var preview = plan.Mode == "RemoteClient"
                ? "Удалённый профиль: локальный сервер не запускается."
                : plan.ServerPath + Environment.NewLine +
                  capability.Describe() + Environment.NewLine + Environment.NewLine +
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
            if (_storePath is not null)
            {
                var profile = LegacyProfileCatalog.Load(_storePath).Profiles.Single(p => p.Id == selected.Id);
                var plan = await Task.Run(() => VramPlanner.Read(selected.ModelPath, profile.RawJson), cancellationToken);
                display += Environment.NewLine + Environment.NewLine + plan.Describe();
            }
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

public sealed record BenchmarkRunOption(StoredBenchmarkRun Run)
{
    public override string ToString() =>
        $"{Run.CompletedAt.LocalDateTime:g} · {Run.ProfileName} · {Run.PromptTokens}/{Run.OutputTokens} · PP {Run.PrefillTokensPerSecond:0.0} / TG {Run.DecodeTokensPerSecond:0.0}";
}
