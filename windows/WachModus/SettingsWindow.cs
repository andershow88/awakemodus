using System.Windows;
using System.Windows.Controls;
using WachModus.Core;

namespace WachModus;

internal sealed class SettingsWindow : Window
{
    private readonly ComboBox theme;
    private readonly CheckBox keyboard;
    public Appearance Appearance => (Appearance)theme.SelectedIndex;
    public bool KeyboardPulse => keyboard.IsChecked == true;

    public SettingsWindow(Appearance appearance, bool keyboardPulse)
    {
        Title = "Einstellungen · WachModus";
        Width = 390;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var content = new StackPanel { Margin = new Thickness(22) };
        content.Children.Add(new TextBlock { Text = "Darstellung", FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) });
        theme = new ComboBox { ItemsSource = new[] { "System", "Hell", "Dunkel" }, SelectedIndex = (int)appearance, Height = 30 };
        content.Children.Add(theme);
        keyboard = new CheckBox { Content = "Zusätzlicher Tastaturimpuls (F15)", IsChecked = keyboardPulse, Margin = new Thickness(0, 22, 0, 8) };
        content.Children.Add(keyboard);
        content.Children.Add(new TextBlock { Text = "Sendet alle 25 Sekunden F15 an Windows. Nur bei Bedarf aktivieren: F15 kann belegte Tastenkürzel auslösen. Windows kann Eingaben an Programme mit höheren Rechten blockieren.", TextWrapping = TextWrapping.Wrap });
        content.Children.Add(new TextBlock { Text = "Beim Öffnen startet WachModus automatisch. Eine Pause hält auch den Timer an. Schließen beendet den Wachmodus.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 18, 0, 18) });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "Abbrechen", IsCancel = true, Padding = new Thickness(14, 6, 14, 6), Margin = new Thickness(0, 0, 8, 0) };
        var save = new Button { Content = "Übernehmen", IsDefault = true, Padding = new Thickness(14, 6, 14, 6) };
        save.Click += (_, _) => DialogResult = true;
        buttons.Children.Add(cancel);
        buttons.Children.Add(save);
        content.Children.Add(buttons);
        Content = content;
    }
}
