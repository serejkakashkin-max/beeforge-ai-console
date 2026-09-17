using Avalonia.Interactivity;
using Avalonia.Controls;
using BeeForge.Next.App.ViewModels;

namespace BeeForge.Next.App;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Opened += async (_, _) =>
        {
            if (ViewModel is { } vm)
            {
                await vm.RefreshRuntimeStatusAsync();
                await vm.RefreshBenchmarkStatusAsync();
            }
        };
    }

    private MainWindowViewModel? ViewModel => DataContext as MainWindowViewModel;

    private async void RefreshRuntime_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm) await vm.RefreshRuntimeStatusAsync();
    }

    private async void StartRuntime_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanControlLocal: true, SelectedProfile: { } selected } vm) return;
        var dialog = new ConfirmRuntimeWindow("Запустить модель?",
            $"BeeForge остановит текущий управляемый сервер и запустит профиль «{selected.Name}». Изменится активный профиль и конфигурация OpenCode после успешного запуска.");
        if (await dialog.ShowDialog<bool>(this)) await vm.StartSelectedAsync();
    }

    private async void StopRuntime_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanControlLocal: true } vm) return;
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

    private async void RefreshTeam_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm) await vm.RefreshTeamAsync();
    }

    private async void RefreshBenchmark_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is { } vm) await vm.RefreshBenchmarkStatusAsync();
    }

    private async void StartBenchmark_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel is not { CanRunBenchmark: true, SelectedProfile: { } selected } vm) return;
        var dialog = new ConfirmRuntimeWindow("Запустить тест скорости?",
            $"BeeForge выполнит разогрев и повторные синтетические замеры профиля «{selected.Name}» на работающей модели. Это займёт вычислительные ресурсы; OpenCode и модель не перезапускаются.");
        if (await dialog.ShowDialog<bool>(this)) await vm.StartBenchmarkAsync();
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
}
