using System.Globalization;
using System.Windows;
using FusionWorkbench.Services;
using FusionWorkbench.ViewModels;

namespace FusionWorkbench;

/// <summary>
/// Application entry point. The window is created in code (instead of StartupUri) so that
/// persisted settings can be loaded and the language dictionaries can be ordered before the
/// first window appears.
/// </summary>
public partial class App : Application
{
    private ResourceDictionary? _englishDictionary;
    private ResourceDictionary? _chineseDictionary;
    private MainViewModel? _viewModel;

    /// <summary>Current language code: "en" or "zh".</summary>
    public static string LanguageCode { get; private set; } = "en";

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        SettingsService.Load();

        EnsureLanguageDictionaries();
        ApplyLanguageCore(SettingsService.Current.Language);

        _viewModel = new MainViewModel();
        MainWindow = new MainWindow { DataContext = _viewModel };
        MainWindow.Show();

        _viewModel.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _viewModel?.Dispose();
        SettingsService.Save();
        base.OnExit(e);
    }

    /// <summary>Resolves a UI string for the active language. Falls back to the key itself.</summary>
    public static string Localize(string key)
    {
        if (Application.Current is null)
        {
            return key;
        }

        object? value = Application.Current.TryFindResource(key);
        return value as string ?? key;
    }

    /// <summary>Resolves a UI string that contains a {0}/{1}... format placeholder.</summary>
    public static string LocalizeFormat(string key, params object?[] args)
    {
        string template = Localize(key);
        try
        {
            return string.Format(CultureInfo.CurrentCulture, template, args);
        }
        catch (FormatException)
        {
            return template;
        }
    }

    /// <summary>Switches the runtime language without restarting (used by the toolbar toggle).</summary>
    public static void SetLanguage(string languageCode)
    {
        if (Application.Current is App app)
        {
            app.ApplyLanguageCore(languageCode);
        }
    }

    private void ApplyLanguageCore(string languageCode)
    {
        string code = string.Equals(languageCode, "zh", StringComparison.OrdinalIgnoreCase) ? "zh" : "en";
        LanguageCode = code;

        EnsureLanguageDictionaries();

        ResourceDictionary target = code == "zh" ? _chineseDictionary! : _englishDictionary!;

        var merged = Resources.MergedDictionaries;
        // Remove whichever language dictionary is currently merged (by reference), then put the
        // requested one first so it wins every DynamicResource lookup.
        for (int i = merged.Count - 1; i >= 0; i--)
        {
            if (ReferenceEquals(merged[i], _englishDictionary) || ReferenceEquals(merged[i], _chineseDictionary))
            {
                merged.RemoveAt(i);
            }
        }

        merged.Insert(0, target);

        SettingsService.Current.Language = code;
        SettingsService.Save();

        _viewModel?.OnLanguageChanged();
    }

    private void EnsureLanguageDictionaries()
    {
        if (_englishDictionary is null)
        {
            // The dictionary declared in App.xaml.
            foreach (ResourceDictionary dictionary in Resources.MergedDictionaries)
            {
                string? source = dictionary.Source?.OriginalString;
                if (!string.IsNullOrEmpty(source) && source.Contains("/Localization/Strings.en.xaml", StringComparison.Ordinal))
                {
                    _englishDictionary = dictionary;
                    break;
                }
            }

            _englishDictionary ??= LoadDictionary("Localization/Strings.en.xaml");
        }

        _chineseDictionary ??= LoadDictionary("Localization/Strings.zh.xaml");
    }

    private static ResourceDictionary LoadDictionary(string path)
    {
        var uri = new Uri($"pack://application:,,,/FusionWorkbench;component/{path}", UriKind.Absolute);
        return new ResourceDictionary { Source = uri };
    }
}
