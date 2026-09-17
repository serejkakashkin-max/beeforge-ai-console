using Avalonia.Controls;
using Avalonia.Layout;
using BeeForge.Next.App.ViewModels;

namespace BeeForge.Next.App;

internal sealed class ScenarioEditorWindow : Window
{
    private readonly TextBox _name = new() { PlaceholderText = "Название сценария" };
    private readonly ListBox _profiles;

    public ScenarioEditorWindow(IReadOnlyList<ProfileOption> profiles)
    {
        Title = "Новый сценарий"; Width = 520; Height = 520; MinWidth = 420; MinHeight = 360;
        _profiles = new ListBox { ItemsSource = profiles, SelectionMode = SelectionMode.Multiple, MinHeight = 260 };
        var save = new Button { Content = "Сохранить", HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "Отмена", HorizontalAlignment = HorizontalAlignment.Right };
        save.Click += (_, _) =>
        {
            var selected = _profiles.SelectedItems?.OfType<ProfileOption>().Select(x => x.Id).ToArray() ?? Array.Empty<string>();
            if (!string.IsNullOrWhiteSpace(_name.Text) && selected.Length > 0) Close(new ScenarioDraft(_name.Text.Trim(), selected));
        };
        cancel.Click += (_, _) => Close(null);
        Content = new StackPanel { Margin = new Avalonia.Thickness(20), Spacing = 12, Children =
        {
            new TextBlock { Text = "Сохраните набор профилей. Сценарий ничего не запускает автоматически.", TextWrapping = Avalonia.Media.TextWrapping.Wrap },
            _name, _profiles, new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right, Children = { cancel, save } }
        }};
    }
}

internal sealed record ScenarioDraft(string Name, IReadOnlyList<string> ProfileIds);
