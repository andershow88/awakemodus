using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using WachModus.Core;
using Duration = WachModus.Core.Duration;

namespace WachModus;

/// <summary>Runs inside the published EXE, on Windows, without user preferences or F15 input.</summary>
internal static class SmokeTests
{
    private sealed class TestPower : IPowerActivity
    {
        public bool Active;
        public void Begin() => Active = true;
        public PulseResult Pulse(bool keyboard) => new(true, true);
        public void End() => Active = false;
        public void Dispose() => End();
    }

    internal static int Run(string[] args)
    {
        var results = new List<object>();
        var failures = 0;
        var report = Argument(args, "--report") ?? "selftest-results.json";
        var snapshots = Argument(args, "--snapshots");
        void Check(bool passed, string name)
        {
            results.Add(new { name, passed });
            if (!passed) failures++;
        }
        MainWindow? window = null;
        try
        {
            using (var system = new WindowsPowerActivity())
            {
                system.Begin();
                system.Begin();
                Check(system.Active, "Windows accepts an idempotent power request");
                Check(system.Pulse(false).Succeeded, "Windows accepts a display/system pulse");
                system.End();
                var previous = WindowsPowerActivity.SetThreadExecutionState(WindowsPowerActivity.Continuous);
                Check(previous != 0 && (previous & (WindowsPowerActivity.DisplayRequired | WindowsPowerActivity.SystemRequired)) == 0,
                    "Stopping clears both native execution requirements");
                system.End();
                Check(!system.Active, "Repeated native stop is safe");
                Check(WindowsPowerActivity.InputSize == (IntPtr.Size == 8 ? 40 : 28), "SendInput structure matches the platform ABI");
            }

            var app = new System.Windows.Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var power = new TestPower();
            var now = 0.0;
            var session = new Session(power, clock: () => now);
            window = new MainWindow(session, new Settings(), testing: true);
            window.Show();
            Pump();
            Click(window.ToggleButton);
            Check(session.IsRunning && power.Active, "Start button starts a session");
            Click(window.HalfHourButton);
            Check(session.Duration == Duration.HalfHour && session.Remaining == 1800, "Duration button starts a 30-minute countdown");
            now = 10;
            session.Tick();
            Click(window.ToggleButton);
            Check(session.State == SessionState.Paused && !power.Active && session.Remaining == 1790, "Pause button releases power and freezes timer");
            now = 100;
            Click(window.ToggleButton);
            Check(session.IsRunning && session.Elapsed == 10, "Resume excludes the pause time");

            foreach (var (name, width, height) in new[] { ("compact", 540.0, 460.0), ("large", 1080.0, 920.0), ("small", 480.0, 400.0), ("wide", 1000.0, 460.0), ("tall", 540.0, 820.0) })
            {
                // Render/layout the real WPF surface; no monitor-size dependency on hosted runners.
                window.Viewport.Width = width;
                window.Viewport.Height = height;
                window.Viewport.Measure(new Size(width, height));
                window.Viewport.Arrange(new Rect(0, 0, width, height));
                window.Viewport.UpdateLayout();
                Pump();
                var expected = LayoutScale.ForSize(width, height);
                Check(Math.Abs(window.SurfaceScale.ScaleX - expected.Scale) < 0.001, $"{name}: content scales with the viewport");
                foreach (var button in new[] { window.ToggleButton, window.SettingsButton, window.HalfHourButton, window.ResetButton })
                {
                    var bounds = button.TransformToAncestor(window.Viewport).TransformBounds(new Rect(button.RenderSize));
                    Check(bounds.Left >= -1 && bounds.Top >= -1 && bounds.Right <= width + 1 && bounds.Bottom <= height + 1 && bounds.Width > 10 && bounds.Height > 10,
                        $"{name}: {button.Name} remains visible and usable");
                }
                var center = window.ToggleButton.TranslatePoint(new Point(window.ToggleButton.ActualWidth / 2, window.ToggleButton.ActualHeight / 2), window.Viewport);
                var hit = window.Viewport.InputHitTest(center) as DependencyObject;
                while (hit is not null && hit != window.ToggleButton) hit = VisualTreeHelper.GetParent(hit);
                Check(hit == window.ToggleButton, $"{name}: scaled button hit-test matches its visible location");
                if (snapshots is not null)
                {
                    foreach (var theme in new[] { Appearance.Light, Appearance.Dark })
                    {
                        window.ApplyTheme(theme);
                        window.Viewport.UpdateLayout();
                        Pump();
                        var bitmap = new RenderTargetBitmap((int)width, (int)height, 96, 96, PixelFormats.Pbgra32);
                        bitmap.Render(window.Viewport);
                        var encoder = new PngBitmapEncoder();
                        encoder.Frames.Add(BitmapFrame.Create(bitmap));
                        Directory.CreateDirectory(snapshots);
                        using var output = File.Create(Path.Combine(snapshots, $"{name}-{theme}.png"));
                        encoder.Save(output);
                    }
                }
            }
            now = 1900;
            session.Tick();
            Check(session.State == SessionState.Finished && !power.Active && session.Remaining == 0, "Expired timer releases power and updates UI");
            Click(window.ToggleButton);
            Click(window.ResetButton);
            Check(session.State == SessionState.Idle && !power.Active, "Reset button stops the session");
            Click(window.ToggleButton);
            window.WindowState = WindowState.Minimized;
            Pump();
            Check(session.IsRunning, "Minimizing keeps the session running");
            window.Close();
            Check(!power.Active && window.IsCleanedUp, "Closing cleans up timers, events and power activity");
            var nativePower = new WindowsPowerActivity();
            var nativeSession = new Session(nativePower);
            window = new MainWindow(nativeSession, new Settings());
            window.Show();
            Pump();
            Check(nativeSession.IsRunning && nativePower.Active && window.IsTimerRunning, "Normal startup activates native power and the real timer");
            Check(window.IsTrayVisible, "Normal startup loads the embedded icon and creates the tray menu");
            Click(window.ToggleButton);
            Check(!nativePower.Active && !window.IsTimerRunning, "Normal pause stops native power and polling");
            Click(window.ToggleButton);
            Check(nativePower.Active && window.IsTimerRunning, "Normal resume restores native power and polling");
            window.Close();
            Check(!nativePower.Active && window.IsCleanedUp, "Normal close removes the tray icon and native power request");
            window = null;
            app.Shutdown(0);
        }
        catch (Exception ex)
        {
            failures++;
            results.Add(new { name = "Unexpected exception", passed = false, details = ex.ToString() });
        }
        finally
        {
            window?.Close();
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(report))!);
            File.WriteAllText(report, JsonSerializer.Serialize(new { passed = failures == 0, failures, checks = results }, new JsonSerializerOptions { WriteIndented = true }));
        }
        return failures == 0 ? 0 : 1;
    }

    private static string? Argument(string[] args, string key)
    {
        var index = Array.IndexOf(args, key);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }
    private static void Click(Button button) => button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    private static void Pump() => Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
}
