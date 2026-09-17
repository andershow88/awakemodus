using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;

namespace WachModus.Core;

public enum SessionState { Idle, Running, Paused, Finished }
public enum Duration { Unlimited = 0, HalfHour = 1800, Hour = 3600, TwoHours = 7200 }
public enum Appearance { System, Light, Dark }
public readonly record struct PulseResult(bool Succeeded = true, bool KeyboardAvailable = true);

public interface IPowerActivity : IDisposable
{
    void Begin();
    PulseResult Pulse(bool keyboard);
    void End();
}

/// <summary>UI-independent session state machine. All calls belong to the UI thread.</summary>
public sealed class Session : INotifyPropertyChanged, IDisposable
{
    public const double PulseInterval = 25;
    private readonly IPowerActivity power;
    private readonly Func<double> clock;
    private double accumulated;
    private double startedAt;
    private double? deadlineElapsed;
    private double? lastPulseAt;
    private bool disposed;

    public Session(IPowerActivity power, Settings? settings = null, Func<double>? clock = null)
    {
        this.power = power;
        this.clock = clock ?? (() => Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency);
        var initial = (settings ?? new Settings()).Validated();
        Duration = initial.Duration;
        KeyboardPulse = initial.KeyboardPulse;
        Remaining = Limit;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public SessionState State { get; private set; }
    public bool IsRunning => State == SessionState.Running;
    public Duration Duration { get; private set; }
    public bool KeyboardPulse { get; set; }
    public double Elapsed { get; private set; }
    public double? Remaining { get; private set; }
    public int NextPulse { get; private set; }
    public PulseResult LastPulse { get; private set; } = new(true, true);
    public string? Error { get; private set; }
    public string ElapsedText => FormatTime(Elapsed);
    public string RemainingText => Remaining is { } value ? FormatTime(value) : "Unbegrenzt";
    public string StateTitle => State switch
    {
        SessionState.Running => "Wachmodus aktiv", SessionState.Paused => "Pausiert",
        SessionState.Finished => "Sitzung beendet", _ => "Bereit"
    };
    public double Progress => Limit is { } total && Remaining is { } remaining
        ? Math.Clamp(1 - remaining / total, 0, 1) : 1;
    private double? Limit => Duration == Duration.Unlimited ? null : (double)Duration;

    public void Toggle() { if (IsRunning) Pause(); else Start(); }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (IsRunning) return;
        try { power.Begin(); }
        catch (Exception ex)
        {
            power.End();
            Error = $"Windows konnte den Wachmodus nicht aktivieren: {ex.Message}";
            Notify();
            return;
        }
        if (State != SessionState.Paused)
        {
            accumulated = 0;
            Elapsed = 0;
            deadlineElapsed = Limit;
            Remaining = Limit;
        }
        Error = null;
        startedAt = clock();
        State = SessionState.Running;
        lastPulseAt = null;
        Tick();
    }

    public void Pause()
    {
        if (!IsRunning) return;
        Tick();
        if (!IsRunning) return;
        accumulated = Elapsed;
        EndActivity();
        State = SessionState.Paused;
        Notify();
    }

    public void Reset()
    {
        EndActivity();
        accumulated = Elapsed = 0;
        Remaining = deadlineElapsed = Limit;
        Error = null;
        State = SessionState.Idle;
        Notify();
    }

    public void SelectDuration(Duration value)
    {
        if (!Enum.IsDefined(value)) throw new ArgumentOutOfRangeException(nameof(value));
        if (value == Duration) return;
        if (IsRunning) Tick();
        Duration = value;
        Remaining = Limit;
        deadlineElapsed = Limit is { } seconds ? Elapsed + seconds : null;
        Notify();
    }

    public void Tick()
    {
        if (!IsRunning) return;
        var now = clock();
        Elapsed = accumulated + Math.Max(0, now - startedAt);
        if (deadlineElapsed is { } deadline)
        {
            Remaining = Math.Max(0, deadline - Elapsed);
            if (Elapsed >= deadline)
            {
                accumulated = Elapsed = deadline;
                EndActivity();
                State = SessionState.Finished;
                Notify();
                return;
            }
        }
        if (lastPulseAt is null || now - lastPulseAt >= PulseInterval)
        {
            LastPulse = power.Pulse(KeyboardPulse);
            lastPulseAt = now;
        }
        NextPulse = Math.Max(0, (int)Math.Ceiling(PulseInterval - (now - lastPulseAt!.Value)));
        Notify();
    }

    private void EndActivity()
    {
        power.End();
        lastPulseAt = null;
        NextPulse = 0;
    }

    public static string FormatTime(double seconds)
    {
        var value = (long)Math.Max(0, Math.Floor(seconds));
        return string.Create(CultureInfo.InvariantCulture, $"{value / 3600:00}:{value / 60 % 60:00}:{value % 60:00}");
    }

    private void Notify() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));

    public void Dispose()
    {
        if (disposed) return;
        EndActivity();
        power.Dispose();
        State = SessionState.Idle;
        disposed = true;
        PropertyChanged = null;
    }
}
