using WachModus.Core;
using Xunit;

namespace WachModus.Tests;

public sealed class SessionTests
{
    private sealed class Power : IPowerActivity
    {
        public bool Active, Fail, Keyboard;
        public int Starts, Pulses;
        public PulseResult Result = new(true, true);
        public void Begin() { Starts++; if (Fail) throw new InvalidOperationException("test failure"); Active = true; }
        public PulseResult Pulse(bool keyboard) { Pulses++; Keyboard = keyboard; return Result; }
        public void End() => Active = false;
        public void Dispose() => End();
    }

    [Fact] public void StartIsIdempotentAndKeyboardIsOptIn()
    {
        var power = new Power();
        using var session = new Session(power);
        session.Start(); session.Start();
        Assert.True(session.IsRunning); Assert.True(power.Active); Assert.Equal(1, power.Starts);
        Assert.Equal(1, power.Pulses); Assert.False(power.Keyboard);
    }

    [Fact] public void PulseOccursOnlyEvery25Seconds()
    {
        var now = 0.0; var power = new Power();
        using var session = new Session(power, clock: () => now);
        session.Start(); now = 24; session.Tick();
        Assert.Equal(1, power.Pulses); Assert.Equal(1, session.NextPulse);
        now = 25; session.Tick(); Assert.Equal(2, power.Pulses); Assert.Equal(25, session.NextPulse);
    }

    [Fact] public void PauseReleasesPowerAndFreezesTime()
    {
        var now = 0.0; var power = new Power();
        using var session = new Session(power, new Settings(Duration.HalfHour), () => now);
        session.Start(); now = 10; session.Pause();
        Assert.False(power.Active); Assert.Equal(1790, session.Remaining);
        now = 100; session.Tick(); Assert.Equal(10, session.Elapsed); Assert.Equal(1, power.Pulses);
        session.Start(); now = 105; session.Tick();
        Assert.Equal(15, session.Elapsed); Assert.Equal(1785, session.Remaining);
    }

    [Theory]
    [InlineData(Duration.HalfHour)] [InlineData(Duration.Hour)] [InlineData(Duration.TwoHours)]
    public void DeadlineStopsBeforeAnotherPulse(Duration duration)
    {
        var now = 0.0; var power = new Power();
        using var session = new Session(power, new Settings(duration), () => now);
        session.Start(); now = (double)duration + 900; session.Tick();
        Assert.Equal(SessionState.Finished, session.State); Assert.False(power.Active);
        Assert.Equal(0, session.Remaining); Assert.Equal((double)duration, session.Elapsed); Assert.Equal(1, power.Pulses);
        session.Start(); Assert.True(power.Active); Assert.Equal(0, session.Elapsed); Assert.Equal((double)duration, session.Remaining);
    }

    [Fact] public void DurationChangesCountFromSelection()
    {
        var now = 0.0; using var session = new Session(new Power(), clock: () => now);
        session.Start(); now = 40; session.SelectDuration(Duration.HalfHour);
        Assert.Equal(1800, session.Remaining); Assert.Equal(40, session.Elapsed);
        now = 45; session.Tick(); Assert.Equal(1795, session.Remaining);
        session.SelectDuration(Duration.HalfHour); Assert.Equal(1795, session.Remaining);
        session.SelectDuration(Duration.Unlimited); now = 999999; session.Tick();
        Assert.True(session.IsRunning); Assert.Null(session.Remaining);
    }

    [Fact] public void ChangingDurationWhilePausedPreservesElapsedTime()
    {
        var now = 0.0; using var session = new Session(new Power(), clock: () => now);
        session.Start(); now = 10; session.Pause(); session.SelectDuration(Duration.Hour);
        now = 100; session.Start(); now = 110; session.Tick();
        Assert.Equal(20, session.Elapsed); Assert.Equal(3590, session.Remaining);
    }

    [Fact] public void PauseAtDeadlineRemainsFinished()
    {
        var now = 0.0; using var session = new Session(new Power(), new Settings(Duration.HalfHour), () => now);
        session.Start(); now = 1800; session.Pause(); Assert.Equal(SessionState.Finished, session.State);
    }

    [Fact] public void ResetAndDisposeReleasePower()
    {
        var power = new Power(); var session = new Session(power);
        session.Start(); session.Reset(); Assert.False(power.Active); Assert.Equal(0, session.Elapsed);
        Assert.Equal(SessionState.Idle, session.State);
        session.Start(); session.Dispose(); session.Dispose(); Assert.False(power.Active);
        Assert.Throws<ObjectDisposedException>(session.Start);
    }

    [Fact] public void FailedStartCanBeRetriedWithoutFalseActiveState()
    {
        var power = new Power { Fail = true }; using var session = new Session(power);
        session.Start(); Assert.False(session.IsRunning); Assert.False(power.Active); Assert.NotNull(session.Error);
        power.Fail = false; session.Start(); Assert.True(session.IsRunning); Assert.Null(session.Error);
    }

    [Fact] public void FailedPulseAndUnavailableKeyboardAreReported()
    {
        var power = new Power { Result = new(false, false) }; using var session = new Session(power);
        session.KeyboardPulse = true; session.Start();
        Assert.True(power.Keyboard); Assert.False(session.LastPulse.Succeeded); Assert.False(session.LastPulse.KeyboardAvailable);
        Assert.True(session.IsRunning);
    }

    [Fact] public void InactiveTickAndPauseDoNotSendPulses()
    {
        var power = new Power(); using var session = new Session(power);
        session.Tick(); session.Pause(); Assert.Equal(0, power.Pulses); Assert.Equal(SessionState.Idle, session.State);
    }

    [Fact] public void InvalidDurationIsRejected()
    {
        using var session = new Session(new Power());
        Assert.Throws<ArgumentOutOfRangeException>(() => session.SelectDuration((Duration)13));
    }

    [Theory] [InlineData(0, "00:00:00")] [InlineData(-5, "00:00:00")] [InlineData(3661.9, "01:01:01")] [InlineData(360000, "100:00:00")]
    public void TimeFormattingSupportsLongSessions(double seconds, string expected) => Assert.Equal(expected, Session.FormatTime(seconds));

    [Fact] public void ProgressTracksRemainingTime()
    {
        var now = 0.0; using var session = new Session(new Power(), new Settings(Duration.Hour), () => now);
        session.Start(); now = 1800; session.Tick(); Assert.Equal(0.5, session.Progress);
        now = 9000; session.Tick(); Assert.Equal(1, session.Progress);
    }

    [Theory]
    [InlineData(540, 460, 1)] [InlineData(1080, 920, 2)] [InlineData(810, 690, 1.5)]
    [InlineData(1000, 460, 1)] [InlineData(540, 820, 1)] [InlineData(480, 400, 0.8695652173913043)]
    public void WholeLayoutScalesAndFillsViewport(double width, double height, double scale)
    {
        var result = LayoutScale.ForSize(width, height);
        Assert.Equal(scale, result.Scale, 8);
        Assert.Equal(width, result.Width * result.Scale, 8); Assert.Equal(height, result.Height * result.Scale, 8);
    }

    [Fact] public void InvalidLayoutSizeHasSafeDefaults() => Assert.Equal(new LayoutScale(1, 540, 460), LayoutScale.ForSize(double.NaN, 0));
    [Fact] public void ErrorMessageReceivesExtraLayoutRoom() => Assert.Equal(520, LayoutScale.ForSize(540, 460, true).Height, 8);
}
