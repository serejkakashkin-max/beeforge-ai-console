using System.Text.Json.Nodes;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using BeeForge.Next.Core.Profiles;

namespace BeeForge.Next.App;

internal sealed class ProfileEditorWindow : Window
{
    private readonly JsonObject _profile;
    private readonly Dictionary<string, Func<JsonNode?>> _readers = new();

    public ProfileEditorWindow(string json)
    {
        _profile = JsonNode.Parse(json)!.AsObject();
        Title = "Настройки профиля BeeForge";
        Width = 800; Height = 740; MinWidth = 620; MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.Parse("#152437"));
        Foreground = Brushes.White;
        var sections = new TabControl();
        AddSection(sections, "Основные", new[] {
            ("name", "Название"), ("alias", "Имя модели в OpenCode"), ("connectionMode", "Подключение"),
            ("modelPath", "Файл модели GGUF"), ("serverPath", "llama-server.exe"),
            ("remoteBaseUrl", "Удалённый API"), ("context", "Контекст"), ("host", "Адрес сервера"),
            ("port", "Порт"), ("openCodeSync", "Синхронизация OpenCode"), ("openCodeOutput", "Лимит ответа OpenCode") });
        AddSection(sections, "Производительность", new[] {
            ("gpuLayers", "Слои GPU (all или число)"), ("batch", "Batch"), ("ubatch", "UBatch"),
            ("threads", "Потоки генерации"), ("threadsBatch", "Потоки промпта"),
            ("parallel", "Параллельные запросы"), ("flashAttention", "Flash Attention"),
            ("cacheReuse", "Повторное использование кэша"), ("noMmap", "Отключить mmap"),
            ("cpuMoeLayers", "Слои CPU MoE"), ("cpuMoeAll", "Все эксперты MoE на CPU"),
            ("tensorOverride", "Tensor override") });
        AddSection(sections, "Кэш и генерация", new[] {
            ("kvK", "Тип K-кэша"), ("kvV", "Тип V-кэша"), ("kvTailTokens", "Токенов в хвосте KV"),
            ("kvTailType", "Тип хвоста KV"), ("reasoningEnabled", "Рассуждения"),
            ("reasoningBudget", "Бюджет рассуждений"), ("reasoningPreserve", "Сохранять рассуждения"),
            ("mtpEnabled", "MTP"), ("mtpNMax", "MTP N max"), ("temperature", "Температура"),
            ("topP", "Top P"), ("topK", "Top K"), ("minP", "Min P"), ("repeatPenalty", "Штраф повторов") });
        AddSection(sections, "Vision и дополнительные", new[] {
            ("visionEnabled", "Vision"), ("mmprojPath", "Проектор MMProj"),
            ("visionOffload", "Проектор на GPU"), ("advancedArgs", "Дополнительные аргументы (JSON)") });
        var error = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.Salmon };
        var save = new Button { Content = "Сохранить", Padding = new Thickness(20, 9) };
        save.Click += (_, _) =>
        {
            try
            {
                foreach (var (key, read) in _readers) _profile[key] = read();
                var result = ProfileStoreEditor.ParseProfile(_profile.ToJsonString());
                Close(result.ToJsonString());
            }
            catch (Exception ex) { error.Text = ex is System.Text.Json.JsonException ? "Проверьте числа и JSON дополнительных аргументов." : ex.Message; }
        };
        var cancel = new Button { Content = "Отмена", Padding = new Thickness(20, 9) };
        cancel.Click += (_, _) => Close((string?)null);
        var footer = new StackPanel { Spacing = 10, Margin = new Thickness(0, 12, 0, 0), Children = {
            error, new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right,
                Spacing = 10, Children = { cancel, save } } } };
        var layout = new Grid { RowDefinitions = new RowDefinitions("*,Auto"), Margin = new Thickness(20) };
        layout.Children.Add(sections); Grid.SetRow(footer, 1); layout.Children.Add(footer);
        Content = layout;
    }

    private void AddSection(TabControl tabs, string title, IEnumerable<(string Key, string Label)> fields)
    {
        var panel = new StackPanel { Spacing = 12, Margin = new Thickness(8, 16) };
        foreach (var (key, label) in fields)
        {
            var value = _profile[key];
            if (value is null && key != "connectionMode" && key != "remoteBaseUrl") continue;
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("220,*") };
            row.Children.Add(new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap,
                VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) });
            Control control;
            if (key == "connectionMode")
            {
                var combo = new ComboBox { ItemsSource = new[] { "LocalHost", "RemoteClient" },
                    SelectedItem = value?.GetValue<string>() ?? "LocalHost", HorizontalAlignment = HorizontalAlignment.Stretch };
                _readers[key] = () => JsonValue.Create(combo.SelectedItem?.ToString() ?? "LocalHost");
                control = combo;
            }
            else if (value is JsonValue boolean && boolean.TryGetValue<bool>(out var flag))
            {
                var checkbox = new CheckBox { IsChecked = flag };
                _readers[key] = () => JsonValue.Create(checkbox.IsChecked == true);
                control = checkbox;
            }
            else
            {
                var numeric = value is JsonValue number && number.GetValueKind() == System.Text.Json.JsonValueKind.Number;
                var text = new TextBox { Text = value?.ToString() ?? "", MinWidth = 220,
                    AcceptsReturn = key == "advancedArgs", MinHeight = key == "advancedArgs" ? 140 : 32 };
                _readers[key] = () => key == "advancedArgs" ? JsonNode.Parse(text.Text ?? "[]") :
                    numeric ? JsonNode.Parse(text.Text ?? "0") : JsonValue.Create(text.Text ?? "");
                control = text;
                if (key is "modelPath" or "serverPath" or "mmprojPath")
                {
                    var browse = new Button { Content = "…", Margin = new Thickness(6, 0, 0, 0) };
                    browse.Click += async (_, _) =>
                    {
                        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions {
                            Title = label, AllowMultiple = false,
                            FileTypeFilter = new[] { new FilePickerFileType(key == "serverPath" ? "Runtime" : "GGUF") {
                                Patterns = new[] { key == "serverPath" ? "*.exe" : "*.gguf" } } } });
                        if (files.Count > 0 && files[0].TryGetLocalPath() is { } path) text.Text = path;
                    };
                    var picker = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
                    picker.Children.Add(text); Grid.SetColumn(browse, 1); picker.Children.Add(browse);
                    control = picker;
                }
            }
            Grid.SetColumn(control, 1); row.Children.Add(control); panel.Children.Add(row);
        }
        tabs.Items.Add(new TabItem { Header = title, Content = new ScrollViewer { Content = panel } });
    }
}
