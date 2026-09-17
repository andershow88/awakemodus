using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using WachModus.Core;

namespace WachModus;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        try
        {
            if (args.Contains("--selftest")) return SmokeTests.Run(args);
            using var mutex = new Mutex(true, @"Local\WachModus.andershow88", out var created);
            if (!created)
            {
                var existing = FindWindow(null, "WachModus");
                if (existing != IntPtr.Zero) { ShowWindow(existing, 9); SetForegroundWindow(existing); }
                return 0;
            }
            try
            {
                var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WachModus", "settings.json");
                var store = new SettingsStore(path);
                var settings = store.Load();
                using var session = new Session(new WindowsPowerActivity(), settings);
                var app = new System.Windows.Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
                return app.Run(new MainWindow(session, settings, store));
            }
            finally { mutex.ReleaseMutex(); }
        }
        catch (Exception ex)
        {
            if (!args.Contains("--selftest"))
                MessageBox.Show($"WachModus konnte nicht ausgeführt werden.\n\n{ex.Message}", "WachModus", MessageBoxButton.OK, MessageBoxImage.Error);
            return 1;
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string? className, string title);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetForegroundWindow(IntPtr window);
}
