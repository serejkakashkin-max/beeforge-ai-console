using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace BeeForge.Next.App;

internal sealed class ConfirmRuntimeWindow : Window
{
    public ConfirmRuntimeWindow(string title, string message)
    {
        Title = title;
        Width = 490;
        Height = 240;
        MinWidth = 440;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.Parse("#1B2B3C"));
        Foreground = new SolidColorBrush(Color.Parse("#EAF2F7"));

        var cancel = new Button { Content = "Отмена", Padding = new Thickness(17, 8) };
        cancel.Click += (_, _) => Close(false);
        var proceed = new Button
        {
            Content = "Подтвердить действие",
            Padding = new Thickness(17, 8),
            Background = new SolidColorBrush(Color.Parse("#176E68")),
            Foreground = Brushes.White
        };
        proceed.Click += (_, _) => Close(true);
        Content = new StackPanel
        {
            Margin = new Thickness(24),
            Spacing = 18,
            Children =
            {
                new TextBlock { Text = title, FontSize = 23, FontWeight = FontWeight.SemiBold },
                new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, Foreground = new SolidColorBrush(Color.Parse("#B8C9D3")) },
                new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    HorizontalAlignment = HorizontalAlignment.Right,
                    Spacing = 10,
                    Children = { cancel, proceed }
                }
            }
        };
    }
}
