namespace FusionWorkbench.Services;

/// <summary>
/// Weather / earth module.
///
/// Chosen approach (documented in windows/README.md):
/// the macOS original shows a Nullschool earth map (WKWebView at https://earth.nullschool.net/).
/// This Windows port mirrors that with a Microsoft.Web.WebView2 control in WeatherCard, and this
/// service keeps the knowledge about the target URL and the failure classification in one place.
/// Open-Meteo was deliberately NOT added as a second source: one primary, least-fragile approach
/// keeps the code, the failure modes and the README small.
///
/// Failure handling (no fake data, ever):
///   - WebView2 runtime missing         -> "Msg_WebView2Missing"
///   - EnsureCoreWebView2Async fails    -> "Msg_WebViewInitFailed"
///   - Navigation fails (e.g. no internet) -> "Msg_WebLoadFailed"
/// </summary>
public static class WeatherService
{
    /// <summary>The earth map shown by the weather card (same URL as the macOS WKWebView).</summary>
    public const string EarthUrl = "https://earth.nullschool.net/";

    /// <summary>
    /// Per-user WebView2 data folder (named sub-folder of the default user data folder) so
    /// cookies / cache from the map do not pollute other WebView2 apps.
    /// </summary>
    public const string UserDataFolderName = "FusionWorkbenchWebView2";

    /// <summary>
    /// Classifies a failure thrown while creating the WebView2 environment / core web view.
    /// Returns the localization key plus an optional detail argument.
    /// </summary>
    public static (string ReasonKey, string? Detail) ClassifyStartupFailure(Exception exception)
    {
        string typeName = exception.GetType().FullName ?? exception.GetType().Name;

        // Avoid a hard dependency on the exact exception type name from the WebView2 runtime.
        if (exception.GetType().Name.Contains("WebView2RuntimeNotFoundException", StringComparison.Ordinal))
        {
            return ("Msg_WebView2Missing", null);
        }

        string detail = exception.Message.Trim();
        if (detail.Length > 200)
        {
            detail = detail[..200];
        }

        return ("Msg_WebViewInitFailed", string.IsNullOrEmpty(detail) ? typeName : detail);
    }

    /// <summary>Formats a navigation failure (CoreWebView2 WebErrorStatus) for the UI.</summary>
    public static string DescribeNavigationFailure(string webErrorStatus)
    {
        return string.IsNullOrWhiteSpace(webErrorStatus) ? "navigation failed" : webErrorStatus;
    }
}
