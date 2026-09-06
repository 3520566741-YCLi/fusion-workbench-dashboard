using System.IO;
using System.Text.Json;

namespace FusionWorkbench.Services;

/// <summary>User-configurable application settings.</summary>
public sealed class AppSettings
{
    /// <summary>"en" or "zh".</summary>
    public string Language { get; set; } = "en";

    /// <summary>Numeric MakerWorld user id from the user's profile URL. Empty disables the card.</summary>
    public string MakerWorldUserId { get; set; } = string.Empty;
}

/// <summary>
/// Persists <see cref="AppSettings"/> as plain JSON in %LOCALAPPDATA%\FusionWorkbench\settings.json.
/// Load/save failures are deliberately swallowed so a read-only or missing profile never breaks
/// the dashboard; defaults simply apply.
/// </summary>
public static class SettingsService
{
    private static readonly string DirectoryPath =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FusionWorkbench");

    private static readonly string FilePath = Path.Combine(DirectoryPath, "settings.json");

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static AppSettings Current { get; } = new();

    public static void Load()
    {
        try
        {
            if (!File.Exists(FilePath))
            {
                return;
            }

            string json = File.ReadAllText(FilePath);
            var loaded = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
            if (loaded is null)
            {
                return;
            }

            Current.Language = string.IsNullOrEmpty(loaded.Language) ? "en" : loaded.Language;
            Current.MakerWorldUserId = loaded.MakerWorldUserId ?? string.Empty;
        }
        catch (Exception)
        {
            // Missing/corrupt settings are not fatal: keep defaults.
        }
    }

    public static void Save()
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            string json = JsonSerializer.Serialize(Current, JsonOptions);
            File.WriteAllText(FilePath, json);
        }
        catch (Exception)
        {
            // Best effort only.
        }
    }
}
