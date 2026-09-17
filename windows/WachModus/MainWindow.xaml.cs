using System;
using System.ComponentModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using WachModus.Core;
using Forms = System.Windows.Forms;
using Duration = WachModus.Core.Duration;

namespace WachModus;

public partial class MainWindow : Window
{
    internal Session Session { get; }
    private readonly SettingsStore? store;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly bool testing;
    private Forms.NotifyIcon? tray;
    private Forms.ContextMenuStrip? trayMenu;
    private Forms.ToolStripMenuItem? trayStatus, trayTime, trayToggle;
    private Appearance appearance;
    private bool closed;
    internal bool IsCleanedUp => closed && !timer.IsEnabled && tray is null;
    internal bool IsTrayVisible => tray?.Visible == true;
    internal bool IsTimerRunning => timer.IsEnabled;

    internal MainWindow(Session session, Settings settings, SettingsStore? store = null, bool testing = false)
    {
        Session = session;
        appearance = settings.Appearance;
        this.store = store;
        this.testing = testing;
        InitializeComponent();
        ApplyTheme();
        Session.PropertyChanged += SessionChanged;
        timer.Tick += TimerTick;
        Loaded += WindowLoaded;
        Closed += WindowClosed;
        PreviewKeyDown += KeyPressed;
        SystemEvents.UserPreferenceChanged += PreferencesChanged;
        SystemEvents.PowerModeChanged += PowerModeChanged;
        UpdateView();
    }

    private void WindowLoaded(object sender, RoutedEventArgs e)
    {
        if (!testing) { CreateTray(); Session.Start(); }
        UpdateScale();
    }

    private void TimerTick(object? sender, EventArgs e) => Session.Tick();
    private void SessionChanged(object? sender, PropertyChangedEventArgs e) => UpdateView();
    private void PreferencesChanged(object sender, UserPreferenceChangedEventArgs e) => Dispatcher.BeginInvoke(() => ApplyTheme());
    private void PowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume) Dispatcher.BeginInvoke(Session.Tick);
    }

    private void UpdateView()
    {
        if (closed) return;
        StateLabel.Text = $"{(Session.IsRunning ? "●" : "○")}  {Session.StateTitle}";
        Headline.Text = Session.State switch
        {
            SessionState.Running => "Dein PC\nbleibt wach.", SessionState.Paused => "Zeit für\neine Pause.",
            SessionState.Finished => "Deine Sitzung\nist geschafft.", _ => "Bereit, wenn\ndu es bist."
        };
        Description.Text = Session.State switch
        {
            SessionState.Running => "Für Downloads, Präsentationen\nund alles, was noch Zeit braucht.",
            SessionState.Paused => "Der Wachmodus pausiert.\nMach weiter, wenn es für dich passt.",
            SessionState.Finished => "Der Timer ist abgelaufen.\nDein PC darf wieder zur Ruhe kommen.",
            _ => "Wähle deine Laufzeit und starte\nentspannt in die nächste Sitzung."
        };
        ElapsedLabel.Text = Session.ElapsedText;
        RemainingLabel.Text = Session.RemainingText;
        RemainingHeading.Text = Session.Duration == Duration.Unlimited ? "LAUFZEIT" : "VERBLEIBEND";
        PulseLabel.Text = !Session.IsRunning ? "Inaktiv" : !Session.LastPulse.Succeeded ? "Nicht gesendet"
            : Session.KeyboardPulse && !Session.LastPulse.KeyboardAvailable ? "F15 blockiert"
            : Session.NextPulse == Core.Session.PulseInterval ? "Gerade eben" : $"in {Session.NextPulse} s";
        ToggleButton.Content = Session.IsRunning ? "Ⅱ  Pausieren" : Session.State == SessionState.Paused ? "▶  Fortsetzen" : "▶  Wachmodus starten";
        ResetButton.IsEnabled = Session.State != SessionState.Idle;
        ErrorLabel.Text = Session.Error ?? "";
        ErrorLabel.Visibility = Session.Error is null ? Visibility.Collapsed : Visibility.Visible;
        OrbitLabel.Text = Session.IsRunning ? "ALLES WACH" : Session.State == SessionState.Finished ? "GESCHAFFT" : "DURCHATMEN";
        CoffeeGlyph.Text = Session.State == SessionState.Finished ? "✓" : "☕";
        ProgressArc.Opacity = Session.IsRunning ? 1 : 0.35;
        var fraction = Session.Duration == Duration.Unlimited ? 0.76 : Math.Clamp(Session.Progress, 0.001, 0.9999);
        var end = new Point(64 + 50 * Math.Sin(2 * Math.PI * fraction), 64 - 50 * Math.Cos(2 * Math.PI * fraction));
        ProgressArc.Data = new PathGeometry([new PathFigure(new Point(64, 14),
            [new ArcSegment(end, new Size(50, 50), 0, fraction > 0.5, SweepDirection.Clockwise, true)], false)]);
        foreach (var button in new[] { UnlimitedButton, HalfHourButton, HourButton, TwoHoursButton })
        {
            var selected = (int)Session.Duration == int.Parse((string)button.Tag, CultureInfo.InvariantCulture);
            button.SetResourceReference(BackgroundProperty, selected ? "AccentSoft" : "Panel");
            button.SetResourceReference(ForegroundProperty, selected ? "Accent" : "Muted");
            button.SetResourceReference(BorderBrushProperty, selected ? "Accent" : "Line");
        }
        if (trayStatus is not null) trayStatus.Text = Session.StateTitle;
        if (trayTime is not null) trayTime.Text = Session.Duration == Duration.Unlimited ? $"Aktive Zeit: {Session.ElapsedText}" : $"Verbleibend: {Session.RemainingText}";
        if (trayToggle is not null) trayToggle.Text = Session.IsRunning ? "Pausieren" : Session.State == SessionState.Paused ? "Fortsetzen" : "Wachmodus starten";
        if (tray is not null) tray.Text = $"WachModus · {Session.StateTitle}";
        if (Session.IsRunning && !testing) timer.Start(); else timer.Stop();
        UpdateScale();
    }

    private void ResizeSurface(object sender, SizeChangedEventArgs e) => UpdateScale();
    private void UpdateScale()
    {
        if (Surface is null || Viewport.ActualWidth <= 0 || Viewport.ActualHeight <= 0) return;
        var layout = LayoutScale.ForSize(Viewport.ActualWidth, Viewport.ActualHeight, Session.Error is not null);
        Surface.Width = layout.Width;
        Surface.Height = layout.Height;
        SurfaceScale.ScaleX = SurfaceScale.ScaleY = layout.Scale;
    }

    internal void ApplyTheme(Appearance? value = null)
    {
        if (value is { } newValue) appearance = newValue;
        var dark = appearance == Appearance.Dark || appearance == Appearance.System && SystemIsDark();
        string[] names = ["BackgroundBrush", "Panel", "Ink", "Muted", "Accent", "AccentStrong", "AccentSoft", "Line"];
        string[] colors = dark
            ? ["#0A0E1A", "#101627", "#E9EDF6", "#A3B0CC", "#6EA8FF", "#2563EB", "#1A2B4F", "#22304F"]
            : ["#F4F6FB", "#FFFFFF", "#131A2A", "#4B5872", "#2563EB", "#1D4ED8", "#DBEAFE", "#D2DCEC"];
        for (var i = 0; i < names.Length; i++) Resources[names[i]] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(colors[i]));
    }

    private static bool SystemIsDark()
    {
        try { return Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) is int value && value == 0; }
        catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or System.IO.IOException) { return false; }
    }

    private void ToggleSession(object sender, RoutedEventArgs e) => Session.Toggle();
    private void ResetSession(object sender, RoutedEventArgs e) => Session.Reset();
    private void ChooseDuration(object sender, RoutedEventArgs e)
    {
        Session.SelectDuration((Duration)int.Parse((string)((Button)sender).Tag, CultureInfo.InvariantCulture));
        SaveSettings();
    }

    private void KeyPressed(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers != ModifierKeys.Control) return;
        if (e.Key == Key.P) { Session.Toggle(); e.Handled = true; }
        if (e.Key == Key.R) { Session.Reset(); e.Handled = true; }
        if (e.Key == Key.Q) { Close(); e.Handled = true; }
    }

    private void OpenSettings(object sender, RoutedEventArgs e)
    {
        var dialog = new SettingsWindow(appearance, Session.KeyboardPulse) { Owner = this };
        if (dialog.ShowDialog() != true) return;
        Session.KeyboardPulse = dialog.KeyboardPulse;
        ApplyTheme(dialog.Appearance);
        SaveSettings();
    }

    private void SaveSettings()
    {
        if (store is not null && !store.Save(new Settings(Session.Duration, Session.KeyboardPulse, appearance)))
            System.Windows.MessageBox.Show(this, "Die Einstellungen konnten nicht gespeichert werden. Die aktuelle Sitzung läuft weiter.", "WachModus", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void CreateTray()
    {
        trayMenu = new Forms.ContextMenuStrip();
        trayStatus = new Forms.ToolStripMenuItem { Enabled = false };
        trayTime = new Forms.ToolStripMenuItem { Enabled = false };
        trayToggle = new Forms.ToolStripMenuItem("Pausieren", null, (_, _) => Session.Toggle());
        trayMenu.Items.AddRange([trayStatus, trayTime, new Forms.ToolStripSeparator(), trayToggle]);
        trayMenu.Items.Add("Sitzung zurücksetzen", null, (_, _) => Session.Reset());
        var durations = new Forms.ToolStripMenuItem("Laufzeit ab jetzt");
        foreach (var (title, duration) in new[] { ("Unbegrenzt", Duration.Unlimited), ("30 Minuten", Duration.HalfHour), ("1 Stunde", Duration.Hour), ("2 Stunden", Duration.TwoHours) })
            durations.DropDownItems.Add(title, null, (_, _) => { Session.SelectDuration(duration); SaveSettings(); });
        trayMenu.Items.Add(durations);
        trayMenu.Items.Add(new Forms.ToolStripSeparator());
        trayMenu.Items.Add("WachModus öffnen", null, (_, _) => ShowWindow());
        trayMenu.Items.Add("WachModus beenden", null, (_, _) => Close());
        using var stream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/WachModus.ico"))!.Stream;
        using var sourceIcon = new System.Drawing.Icon(stream);
        tray = new Forms.NotifyIcon { Icon = (System.Drawing.Icon)sourceIcon.Clone(), ContextMenuStrip = trayMenu, Text = "WachModus", Visible = true };
        tray.DoubleClick += (_, _) => ShowWindow();
    }

    private void ShowWindow() { Show(); WindowState = WindowState.Normal; Activate(); }

    private void WindowClosed(object? sender, EventArgs e)
    {
        if (closed) return;
        closed = true;
        timer.Stop();
        timer.Tick -= TimerTick;
        Session.PropertyChanged -= SessionChanged;
        SystemEvents.UserPreferenceChanged -= PreferencesChanged;
        SystemEvents.PowerModeChanged -= PowerModeChanged;
        if (tray is not null) { tray.Visible = false; tray.Icon?.Dispose(); tray.Dispose(); tray = null; }
        trayMenu?.Dispose();
        Session.Dispose();
    }
}
