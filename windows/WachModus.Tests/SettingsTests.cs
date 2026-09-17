using WachModus.Core;
using Xunit;

namespace WachModus.Tests;

public sealed class SettingsTests : IDisposable
{
    private readonly string directory = Path.Combine(Path.GetTempPath(), "WachModus-tests-" + Guid.NewGuid());
    private string FilePath => Path.Combine(directory, "settings.json");
    [Fact] public void MissingFileUsesDefaults() => Assert.Equal(new Settings(), new SettingsStore(FilePath).Load());
    [Fact] public void SettingsRoundTripAndOverwrite()
    {
        var store = new SettingsStore(FilePath);
        var options = new Settings(Duration.Hour, true, Appearance.Dark);
        Assert.True(store.Save(options)); Assert.Equal(options, store.Load());
        Assert.True(store.Save(new Settings())); Assert.Equal(new Settings(), store.Load());
        Assert.Single(Directory.GetFiles(directory));
    }
    [Theory] [InlineData("{broken")] [InlineData("null")] [InlineData("{\"Duration\":7,\"Appearance\":8}")]
    public void CorruptOrUnknownSettingsUseSafeDefaults(string json)
    {
        Directory.CreateDirectory(directory); File.WriteAllText(FilePath, json);
        Assert.Equal(new Settings(), new SettingsStore(FilePath).Load());
    }
    [Fact] public void WriteFailureDoesNotCrashOrLeaveTemporaryFiles()
    {
        Directory.CreateDirectory(directory); Directory.CreateDirectory(FilePath);
        Assert.False(new SettingsStore(FilePath).Save(new Settings()));
        Assert.Empty(Directory.GetFiles(directory));
    }
    public void Dispose() { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
}
