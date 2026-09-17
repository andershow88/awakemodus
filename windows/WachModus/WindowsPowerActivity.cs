using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using WachModus.Core;

namespace WachModus;

internal sealed class WindowsPowerActivity : IPowerActivity
{
    internal const uint Continuous = 0x80000000;
    internal const uint SystemRequired = 1;
    internal const uint DisplayRequired = 2;
    private readonly int threadId = Environment.CurrentManagedThreadId;
    internal bool Active { get; private set; }

    public void Begin()
    {
        CheckThread();
        if (Active) return;
        if (SetThreadExecutionState(Continuous | SystemRequired | DisplayRequired) == 0)
            throw new Win32Exception(Marshal.GetLastWin32Error());
        Active = true;
    }

    public PulseResult Pulse(bool keyboard)
    {
        CheckThread();
        var success = SetThreadExecutionState(SystemRequired | DisplayRequired) != 0;
        var keyboardAvailable = true;
        if (keyboard)
        {
            var inputs = new[] { KeyboardInput(false), KeyboardInput(true) };
            keyboardAvailable = SendInput(2, inputs, Marshal.SizeOf<Input>()) == 2;
            // If only the key-down was accepted, always attempt the matching key-up.
            if (!keyboardAvailable) SendInput(1, [KeyboardInput(true)], Marshal.SizeOf<Input>());
        }
        return new(success, keyboardAvailable);
    }

    public void End()
    {
        CheckThread();
        if (!Active) return;
        if (SetThreadExecutionState(Continuous) == 0)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Der Windows-Wachmodus konnte nicht beendet werden.");
        Active = false;
    }

    public void Dispose() => End();
    private void CheckThread()
    {
        if (threadId != Environment.CurrentManagedThreadId)
            throw new InvalidOperationException("Wachhalte-Aufrufe müssen auf demselben UI-Thread erfolgen.");
    }

    private static Input KeyboardInput(bool up) => new()
    {
        Type = 1,
        Data = new InputUnion { Keyboard = new Keyboard { VirtualKey = 0x7E, Flags = up ? 2u : 0u } }
    };

    [StructLayout(LayoutKind.Sequential)]
    private struct Input { public uint Type; public InputUnion Data; }
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public Keyboard Keyboard;
        [FieldOffset(0)] public Mouse Mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct Keyboard { public ushort VirtualKey, Scan; public uint Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Mouse { public int X, Y; public uint MouseData, Flags, Time; public UIntPtr Extra; }
    internal static int InputSize => Marshal.SizeOf<Input>();

    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern uint SetThreadExecutionState(uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int size);
}
