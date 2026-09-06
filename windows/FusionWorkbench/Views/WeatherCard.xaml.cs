using System.IO;
using System.Windows;
using System.Windows.Controls;
using FusionWorkbench.Services;
using FusionWorkbench.ViewModels;
using Microsoft.Web.WebView2.Core;

namespace FusionWorkbench.Views;

/// <summary>
/// Hosts the Nullschool earth map in a WebView2 control (mirroring the macOS WKWebView card).
/// WebView2 creation is asynchronous: if the runtime is missing, or the map cannot be reached
/// (no internet), the card falls back to an explicit Unavailable overlay with a reason.
/// </summary>
public partial class WeatherCard : UserControl
{
    private bool _coreReady;
    private bool _loadAttempted;

    public WeatherCard()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        Loaded -= OnLoaded;
        await LoadOrReloadAsync();
    }

    private async void OnRetryClick(object sender, RoutedEventArgs e)
    {
        await LoadOrReloadAsync();
    }

    private async Task LoadOrReloadAsync()
    {
        var vm = DataContext as WeatherCardViewModel;
        vm?.MarkLoading();

        try
        {
            if (!_coreReady)
            {
                string userDataFolder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "FusionWorkbench",
                    WeatherService.UserDataFolderName);

                Directory.CreateDirectory(userDataFolder);
                CoreWebView2Environment environment = await CoreWebView2Environment.CreateAsync(null, userDataFolder);

                await EarthView.EnsureCoreWebView2Async(environment);

                CoreWebView2? core = EarthView.CoreWebView2;
                if (core is null)
                {
                    vm?.MarkFailed("Msg_WebViewInitFailed", "core web view unavailable");
                    return;
                }

                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.IsStatusBarEnabled = false;
                EarthView.NavigationCompleted += OnNavigationCompleted;
                _coreReady = true;
            }

            // Loaded earlier and just retrying.
            if (_loadAttempted)
            {
                EarthView.Reload();
            }
            else
            {
                EarthView.Source = new Uri(WeatherService.EarthUrl);
                _loadAttempted = true;
            }
        }
        catch (Exception ex)
        {
            (string reasonKey, string? detail) = WeatherService.ClassifyStartupFailure(ex);
            vm?.MarkFailed(reasonKey, detail);
        }
    }

    private void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        var vm = DataContext as WeatherCardViewModel;
        if (vm is null)
        {
            return;
        }

        if (e.IsSuccess)
        {
            vm.MarkAvailable();
        }
        else
        {
            // e.g. no internet connection: HostUnreachable / ConnectionAborted / ...
            vm.MarkFailed("Msg_WebLoadFailed", WeatherService.DescribeNavigationFailure(e.WebErrorStatus.ToString()));
        }
    }
}
