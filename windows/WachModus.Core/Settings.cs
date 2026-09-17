using System.Text.Json;

namespace WachModus.Core;

public sealed record Settings(Duration Duration = Duration.Unlimited, bool KeyboardPulse = false,
                              Appearance Appearance = Appearance.System)
{
    public Settings Validated() => this with
    {
        Duration = Enum.IsDefined(Duration) ? Duration : Duration.Unlimited,
        Appearance = Enum.IsDefined(Appearance) ? Appearance : Appearance.System
    };
}

public sealed class SettingsStore(string path)
{
    public Settings Load()
    {
        try { return (JsonSerializer.Deserialize<Settings>(File.ReadAllText(path)) ?? new Settings()).Validated(); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        { return new Settings(); }
    }

    public bool Save(Settings settings)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
            File.WriteAllText(temporary, JsonSerializer.Serialize(settings.Validated()));
            File.Move(temporary, path, overwrite: true);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return false; }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
    }
}

public readonly record struct LayoutScale(double Scale, double Width, double Height)
{
    public static LayoutScale ForSize(double width, double height, bool hasError = false)
    {
        if (!double.IsFinite(width) || !double.IsFinite(height) || width <= 0 || height <= 0)
            return new(1, 540, 460);
        var scale = Math.Max(0.1, Math.Min(width / 540, height / (hasError ? 520 : 460)));
        return new(scale, width / scale, height / scale);
    }
}
