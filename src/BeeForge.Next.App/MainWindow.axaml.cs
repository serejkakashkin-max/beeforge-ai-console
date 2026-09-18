using Avalonia.Interactivity;
using Avalonia.Controls;
using BeeForge.Next.App.ViewModels;
using BeeForge.Next.Core.Benchmarking;
using Avalonia.Platform.Storage;
using BeeForge.Next.Core.Inference;
using BeeForge.Next.Core.Workspace;
using System.Diagnostics;

namespace BeeForge.Next.App;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Closed += async (_, _) =>
        {
            if (ViewModel is { } vm) await vm.ShutdownTransientServicesAsync();
        };
        Opened += async (_, _) =>
        {
            if (ViewModel is { } vm)
            {
                await vm.RefreshRuntimeStatusAsync();
                await vm.RefreshBenchmarkStatusAsync();
                if (BenchmarkRunsList.ItemCount > 0) BenchmarkRunsList.SelectedIndex = 0;
            }
        };
    }

    private MainWindowViewModel? ViewModel => DataContext as MainWindowViewModel;

    private async void Service_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm || sender is not Button { Tag: string tag } ||
            !Enum.TryParse<ServiceAction>(tag, out var action)) return;
        var explanation = action switch {
            ServiceAction.RemoteEnable => "Модель будет предоставлена устройствам Tailscale. Локальная работа с моделью будет заблокирована до выключения удалённого доступа. Публичный доступ не включается.",
            ServiceAction.RemoteDisable => "Удалённый доступ к модели будет выключен; локальная работа снова станет доступна. Подключённый ноутбук потеряет доступ.",
            ServiceAction.FullAccessEnable => "Агенты смогут выполнять действия без дополнительных подтверждений. Назначенные каждому агенту MCP и skills остаются ограниченными его ролью.",
            ServiceAction.FullAccessDisable => "Будет восстановлен режим разрешений до включения полного доступа.",
            ServiceAction.TelegramStart => "Будет запущен существующий Telegram Bridge с сохранёнными настройками и автозапуском.",
            ServiceAction.TelegramStop => "Telegram Bridge будет остановлен. Модель и OpenCode продолжат работать.",
            _ => null
        };
        if (explanation is not null && !await new ConfirmRuntimeWindow("Подтвердить действие", explanation).ShowDialog<bool>(this)) return;
        await vm.RunServiceAsync(action);
    }

    private void RefreshProfiles_Click(object? sender, RoutedEventArgs e) => ViewModel?.ReloadProfiles();

    private async void HfSearch_Click(object? sender, RoutedEventArgs e) { if (ViewModel is { } vm) await vm.SearchHfAsync(); }
    private async void HfFiles_Click(object? sender, RoutedEventArgs e) { if (ViewModel is { } vm) await vm.LoadHfFilesAsync(); }
    private async void HfDownload_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { SelectedHfFile: not null } vm) return;
        var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = "Папка для GGUF", AllowMultiple = false });
        if (folders.Count == 0) return;
        var path = folders[0].TryGetLocalPath();
        if (!string.IsNullOrWhiteSpace(path)) await vm.DownloadHfAsync(path);
    }

    private async void NewScenario_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        var draft = await new ScenarioEditorWindow(vm.ProfileNames).ShowDialog<ScenarioDraft?>(this);
        if (draft is not null) vm.AddScenario(draft.Name, draft.ProfileIds);
    }
    private void DeleteScenario_Click(object? sender, RoutedEventArgs e) => ViewModel?.DeleteSelectedScenario();
    private void SelectScenarioProfile_Click(object? sender, RoutedEventArgs e) => ViewModel?.SelectScenarioFirstProfile();

    private async void EditProfile_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { SelectedProfile: { } selected } vm) return;
        try
        {
            var snapshot = vm.ReadProfileCatalog();
            var profile = snapshot.Profiles.Single(p => p.Id == selected.Id);
            var edited = await new ProfileEditorWindow(profile.RawJson).ShowDialog<string?>(this);
            if (edited is not null) vm.SaveProfile(snapshot, profile.Id, edited);
        }
        catch (Exception ex) { vm.SetProfileMessage(ex.Message); }
    }

    private async void NewProfile_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        try
        {
            var snapshot = vm.ReadProfileCatalog();
            var basis = snapshot.Profiles.FirstOrDefault(p => p.Id == vm.SelectedProfile?.Id) ?? snapshot.Profiles.First();
            var draft = System.Text.Json.Nodes.JsonNode.Parse(basis.RawJson)!.AsObject();
            draft["name"] = "Новый профиль"; draft["alias"] = "new-model";
            var edited = await new ProfileEditorWindow(draft.ToJsonString()).ShowDialog<string?>(this);
            if (edited is not null) vm.AddProfile(snapshot, edited, false);
        }
        catch (Exception ex) { vm.SetProfileMessage(ex.Message); }
    }

    private void CloneProfile_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { SelectedProfile: { } selected } vm) return;
        try
        {
            var snapshot = vm.ReadProfileCatalog();
            vm.AddProfile(snapshot, snapshot.Profiles.Single(p => p.Id == selected.Id).RawJson, true);
        }
        catch (Exception ex) { vm.SetProfileMessage(ex.Message); }
    }

    private async void DeleteProfile_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { SelectedProfile: { } selected } vm) return;
        try
        {
            var snapshot = vm.ReadProfileCatalog();
            var dialog = new ConfirmRuntimeWindow("Удалить профиль?", $"Будет удалён профиль «{selected.Name}». Файлы модели останутся на диске. Предыдущее состояние профилей будет сохранено в резервной копии.");
            if (await dialog.ShowDialog<bool>(this)) vm.DeleteProfile(snapshot, selected.Id);
        }
        catch (Exception ex) { vm.SetProfileMessage(ex.Message); }
    }

    private async void ImportProfile_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        try
        {
            var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions {
                Title = "Импорт профиля BeeForge", AllowMultiple = false,
                FileTypeFilter = new[] { new FilePickerFileType("JSON") { Patterns = new[] { "*.json" } } } });
            if (files.Count == 0) return;
            await using var stream = await files[0].OpenReadAsync();
            if (stream.Length > 1024 * 1024) throw new IOException("Файл профиля слишком большой.");
            using var reader = new StreamReader(stream);
            var json = await reader.ReadToEndAsync();
            var snapshot = vm.ReadProfileCatalog();
            var edited = await new ProfileEditorWindow(json).ShowDialog<string?>(this);
            if (edited is not null) vm.AddProfile(snapshot, edited, false);
        }
        catch (Exception ex) { vm.SetProfileMessage(ex.Message); }
    }

    private async void ExportProfile_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { SelectedProfile: { } selected } vm) return;
        try
        {
            var profile = vm.ReadProfileCatalog().Profiles.Single(p => p.Id == selected.Id);
            var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions {
                Title = "Экспорт профиля", SuggestedFileName = selected.Id + ".json",
                FileTypeChoices = new[] { new FilePickerFileType("JSON") { Patterns = new[] { "*.json" } } } });
            if (file is null) return;
            await using var stream = await file.OpenWriteAsync();
            stream.SetLength(0);
            await using var writer = new StreamWriter(stream);
            await writer.WriteAsync(profile.RawJson);
            vm.SetProfileMessage("Профиль экспортирован.");
        }
        catch (Exception ex) { vm.SetProfileMessage(ex.Message); }
    }

    private async void RefreshRuntime_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm) await vm.RefreshRuntimeStatusAsync();
    }

    private async void StartRuntime_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanStartLocal: true, SelectedProfile: { } selected } vm) return;
        var dialog = new ConfirmRuntimeWindow("Запустить модель?",
            $"BeeForge остановит текущий управляемый сервер и запустит профиль «{selected.Name}». Изменится активный профиль и конфигурация OpenCode после успешного запуска.");
        if (await dialog.ShowDialog<bool>(this)) await vm.StartSelectedAsync();
    }

    private async void StopRuntime_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanStopLocal: true } vm) return;
        var dialog = new ConfirmRuntimeWindow("Остановить модель?",
            "Будет остановлен только сервер, которым управляет BeeForge на этом ПК. Telegram и OpenCode не закрываются.");
        if (await dialog.ShowDialog<bool>(this)) await vm.StopSelectedAsync();
    }

    private async void ConnectRemote_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanConnectRemote: true, SelectedProfile: { } selected } vm) return;
        var dialog = new ConfirmRuntimeWindow("Подключить удалённую модель?",
            $"BeeForge проверит доступность профиля «{selected.Name}». Только после успешной проверки OpenCode будет переключён на него. Локальная модель не запускается и не останавливается.");
        if (await dialog.ShowDialog<bool>(this)) await vm.ConnectSelectedRemoteAsync();
    }

    private async void ServerLog_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm) await vm.RefreshLogAsync("server");
    }

    private async void ServerOutputLog_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm) await vm.RefreshLogAsync("server-output");
    }

    private async void TelegramLog_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm) await vm.RefreshLogAsync("telegram");
    }

    private void RefreshRuntimeCatalog_Click(object? sender, RoutedEventArgs e) => ViewModel?.RefreshRuntimeCatalog();

    private async void InstallRuntime_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        var dialog = new ConfirmRuntimeWindow("Установить BeeLlama runtime?",
            "Будет скачана рекомендуемая BeeLlama v0.4.6 CUDA 13.3 с проверкой SHA-256. Текущие профили и запущенная модель автоматически переключаться не будут.");
        if (await dialog.ShowDialog<bool>(this)) await vm.InstallRecommendedRuntimeAsync();
    }

    private async void InstallUpstreamRuntime_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm || sender is not Button { Tag: string tag } ||
            !Enum.TryParse<LlamaRuntimeBackend>(tag, out var backend)) return;
        var dialog = new ConfirmRuntimeWindow("Установить upstream llama.cpp?",
            $"Будет скачана последняя подходящая Windows {UpstreamLlamaRuntimeManager.BackendLabel(backend)}-сборка из официального ggml-org/llama.cpp. Она установится отдельно от BeeLlama; текущий профиль и запущенная модель не переключаются автоматически.");
        if (await dialog.ShowDialog<bool>(this)) await vm.InstallUpstreamRuntimeAsync(backend);
    }

    private async void ToggleProxy_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        var dialog = new ConfirmRuntimeWindow("Изменить состояние on-demand proxy?",
            "Proxy слушает только localhost. При первом запросе он может запустить выбранный по model профиль через существующий BeeForge, а после простоя остановить модель, которую сам загрузил.");
        if (await dialog.ShowDialog<bool>(this)) await vm.ToggleProxyAsync();
    }

    private void Help_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm && sender is Button { Tag: string topic }) vm.ShowHelp(topic);
    }

    private async void RefreshTeam_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm) await vm.RefreshTeamAsync();
    }

    private async void RefreshBenchmark_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm)
        {
            await vm.RefreshBenchmarkStatusAsync();
            if (BenchmarkRunsList.ItemCount > 0) BenchmarkRunsList.SelectedIndex = 0;
        }
    }

    private void PresetShort_Click(object? sender, RoutedEventArgs e) => ViewModel?.SetBenchmarkPreset("short");
    private void PresetStandard_Click(object? sender, RoutedEventArgs e) => ViewModel?.SetBenchmarkPreset("standard");
    private void PresetLong_Click(object? sender, RoutedEventArgs e) => ViewModel?.SetBenchmarkPreset("long");

    private async void StartBenchmark_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanRunBenchmark: true, SelectedProfile: { } selected } vm) return;
        var dialog = new ConfirmRuntimeWindow("Запустить тест скорости?",
            $"BeeForge выполнит разогрев и повторные синтетические замеры профиля «{selected.Name}» на работающей модели. Это займёт вычислительные ресурсы; OpenCode и модель не перезапускаются.");
        if (await dialog.ShowDialog<bool>(this))
        {
            await vm.StartBenchmarkAsync();
            if (BenchmarkRunsList.ItemCount > 0) BenchmarkRunsList.SelectedIndex = 0;
        }
    }

    private async void StopBenchmark_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanStopBenchmark: true } vm) return;
        await vm.StopBenchmarkAsync();
    }

    private async void AutoTune_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanAutoTune: true, SelectedProfile: { } selected } vm) return;
        var dialog = new ConfirmRuntimeWindow("Проверить варианты настроек?",
            $"Для профиля «{selected.Name}» будут последовательно загружены временные серверы и выполнены замеры. Это ресурсоёмкая операция; рабочая модель должна быть остановлена. Исходный профиль не меняется.");
        if (await dialog.ShowDialog<bool>(this)) await vm.RunAutoTuneAsync();
    }

    private async void SaveAutoTune_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanSaveTune: true } vm) return;
        var dialog = new ConfirmRuntimeWindow("Создать новый профиль?",
            "Будет создана копия исходного профиля с подобранными параметрами. Исходный и активный профили сохранятся; перед записью будет создана резервная копия файла профилей.");
        if (await dialog.ShowDialog<bool>(this)) vm.SaveAutoTuneProfile();
    }

    private async void ExportBenchmark_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        var selected = BenchmarkRunsList.SelectedItems?.OfType<BenchmarkRunOption>()
            .Select(option => option.Run).ToArray() ?? Array.Empty<StoredBenchmarkRun>();
        if (selected.Length == 0) { vm.SetBenchmarkMessage("Выберите хотя бы один прогон."); return; }
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Сохранить сравнение BeeForge",
            SuggestedFileName = "beeforge-benchmark-comparison.md",
            FileTypeChoices = new[] { new FilePickerFileType("Markdown") { Patterns = new[] { "*.md" } } }
        });
        if (file is null) return;
        try
        {
            await using var stream = await file.OpenWriteAsync();
            using var writer = new StreamWriter(stream);
            await writer.WriteAsync(BenchmarkComparisonReport.Render(selected));
            vm.SetBenchmarkMessage($"Отчёт сравнения сохранён: {file.Path.LocalPath}");
        }
        catch (Exception)
        {
            vm.SetBenchmarkMessage("Не удалось сохранить отчёт. История замеров не изменена.");
        }
    }

    private void OpenBenchmarkFolder_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel?.GetBenchmarkResultsDirectory() is not { } path) return;
        try
        {
            Directory.CreateDirectory(path);
            Process.Start(new ProcessStartInfo("explorer.exe", path) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ViewModel.SetBenchmarkMessage($"Не удалось открыть папку результатов: {ex.GetType().Name}.");
        }
    }
}
