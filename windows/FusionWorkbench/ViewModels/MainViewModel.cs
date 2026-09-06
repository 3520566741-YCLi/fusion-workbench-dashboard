using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;
using System.Windows.Threading;
using FusionWorkbench.Converters;
using FusionWorkbench.Models;
using FusionWorkbench.Services;

namespace FusionWorkbench.ViewModels;

/// <summary>Minimal INotifyPropertyChanged base.</summary>
public abstract class ViewModelBase : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    /// <summary>Raises PropertyChanged for every property (used after a full snapshot swap).</summary>
    protected void RaiseAll()
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));
}

/// <summary>
/// Common card state: availability, header status label + dot brush, body message and the
/// "Updated HH:mm:ss" footer. Subclasses add their data rows.
/// </summary>
public abstract class ModuleCardViewModelBase : ViewModelBase
{
    private bool _isAvailable;
    private string _statusLabel = string.Empty;
    private Brush _statusBrush = Palette.Gray;
    private string _message = string.Empty;
    private string _updatedText = string.Empty;

    public bool IsAvailable
    {
        get => _isAvailable;
        protected set { _isAvailable = value; OnPropertyChanged(); }
    }

    public string StatusLabel
    {
        get => _statusLabel;
        protected set { _statusLabel = value; OnPropertyChanged(); }
    }

    public Brush StatusBrush
    {
        get => _statusBrush;
        protected set { _statusBrush = value; OnPropertyChanged(); }
    }

    public string Message
    {
        get => _message;
        protected set { _message = value; OnPropertyChanged(); }
    }

    public string UpdatedText
    {
        get => _updatedText;
        protected set { _updatedText = value; OnPropertyChanged(); }
    }

    /// <summary>Applies shared status state from a snapshot (or null while waiting).</summary>
    protected void ApplySharedStatus(ModuleSnapshot? snapshot, string availableLabelKey)
    {
        if (snapshot is null)
        {
            IsAvailable = false;
            StatusLabel = App.Localize("Status_Checking");
            StatusBrush = Palette.Amber;
            Message = App.Localize("Msg_WaitingFirstSample");
            UpdatedText = string.Empty;
            return;
        }

        IsAvailable = snapshot.IsAvailable;
        if (snapshot.IsAvailable)
        {
            StatusLabel = App.Localize(availableLabelKey);
            StatusBrush = Palette.Mint;
            Message = string.Empty;
        }
        else
        {
            StatusLabel = App.Localize("Status_Unavailable");
            StatusBrush = Palette.Gray;
            Message = ResolveReason(snapshot);
        }

        UpdatedText = App.LocalizeFormat("Lbl_Updated", FormatTime(snapshot.SampledAt));
    }

    protected static string ResolveReason(ModuleSnapshot snapshot)
    {
        if (string.IsNullOrEmpty(snapshot.ReasonKey))
        {
            return App.Localize("Status_Unavailable");
        }

        return string.IsNullOrEmpty(snapshot.ReasonDetail)
            ? App.Localize(snapshot.ReasonKey)
            : App.LocalizeFormat(snapshot.ReasonKey, snapshot.ReasonDetail);
    }

    /// <summary>Recomputes every localized string from the last snapshot (language switch).</summary>
    public abstract void Relocalize();

    protected static string FormatTime(DateTime value) => value.ToLocalTime().ToString("HH:mm:ss");

    protected static string FormatBytes(ulong bytes)
    {
        const double gb = 1024.0 * 1024.0 * 1024.0;
        const double mb = 1024.0 * 1024.0;

        if (bytes >= gb)
        {
            return $"{bytes / gb:0.0} GB";
        }

        if (bytes >= mb)
        {
            return $"{bytes / mb:0} MB";
        }

        return $"{bytes} B";
    }

    protected static string FormatCount(long? count) => count.HasValue ? count.Value.ToString("N0") : "—";
}

// -------------------------------------------------------------------------------------------
// System card
// -------------------------------------------------------------------------------------------

public sealed class SystemCardViewModel : ModuleCardViewModelBase
{
    private SystemMetricsSnapshot? _snapshot;

    public SystemMetricsSnapshot? Snapshot => _snapshot;

    public string CoresText { get; private set; } = string.Empty;
    public string OsText { get; private set; } = string.Empty;
    public string CpuText { get; private set; } = string.Empty;
    public double CpuUsage { get; private set; }
    public string MemoryText { get; private set; } = string.Empty;
    public double MemoryUsage { get; private set; }
    public string DiskText { get; private set; } = string.Empty;
    public double DiskUsage { get; private set; }

    public void Apply(SystemMetricsSnapshot snapshot)
    {
        _snapshot = snapshot;
        ApplySharedStatus(snapshot, "Status_Monitoring");
        UpdateRows();
    }

    public override void Relocalize()
    {
        ApplySharedStatus(_snapshot, "Status_Monitoring");
        UpdateRows();
    }

    private void UpdateRows()
    {
        var snapshot = _snapshot;
        if (snapshot is null)
        {
            return;
        }

        CoresText = snapshot.ProcessorCount.ToString();
        OsText = snapshot.OsDescription;

        if (snapshot.CpuPercent.HasValue)
        {
            CpuText = $"{Math.Round(snapshot.CpuPercent.Value * 100.0)}%";
            CpuUsage = snapshot.CpuPercent.Value;
        }
        else
        {
            CpuText = App.Localize("Status_Checking");
            CpuUsage = 0;
        }

        MemoryText = snapshot.MemoryTotalBytes > 0
            ? $"{FormatBytes(snapshot.MemoryUsedBytes)} / {FormatBytes(snapshot.MemoryTotalBytes)}"
            : "—";
        MemoryUsage = snapshot.MemoryFraction ?? 0;

        DiskText = snapshot.DiskTotalBytes > 0
            ? $"{FormatBytes(snapshot.DiskFreeBytes)} free / {FormatBytes(snapshot.DiskTotalBytes)}"
            : "—";
        DiskUsage = snapshot.DiskFraction ?? 0;

        RaiseAll();
    }
}

// -------------------------------------------------------------------------------------------
// GitHub card
// -------------------------------------------------------------------------------------------

/// <summary>Localized display row for one recently-updated repository.</summary>
public sealed class GitHubRepoRow
{
    public string Name { get; init; } = string.Empty;
    public string Badge { get; init; } = string.Empty;
    public string StarsText { get; init; } = string.Empty;
}

public sealed class GitHubCardViewModel : ModuleCardViewModelBase
{
    private GitHubSnapshot? _snapshot;

    public string UsernameText { get; private set; } = string.Empty;
    public string JoinedText { get; private set; } = string.Empty;
    public string OrgsText { get; private set; } = string.Empty;
    public string PublicReposText { get; private set; } = "—";
    public string PrivateReposText { get; private set; } = "—";
    public string TotalReposText { get; private set; } = "—";
    public string ForksText { get; private set; } = "—";
    public IReadOnlyList<GitHubRepoRow> RecentRepositories { get; private set; } = Array.Empty<GitHubRepoRow>();

    public void Apply(GitHubSnapshot snapshot)
    {
        _snapshot = snapshot;
        ApplySharedStatus(snapshot, "Status_Connected");
        UpdateRows();
    }

    public override void Relocalize()
    {
        ApplySharedStatus(_snapshot, "Status_Connected");
        UpdateRows();
    }

    private void UpdateRows()
    {
        var snapshot = _snapshot;
        if (snapshot is null)
        {
            return;
        }

        if (!snapshot.IsAvailable)
        {
            RaiseAll();
            return;
        }

        UsernameText = snapshot.Username ?? "—";
        JoinedText = snapshot.AccountCreatedAt.HasValue
            ? snapshot.AccountCreatedAt.Value.ToLocalTime().ToString("yyyy-MM-dd")
            : "—";
        PublicReposText = FormatCount(snapshot.PublicRepoCount);
        PrivateReposText = FormatCount(snapshot.PrivateRepoCount);
        TotalReposText = FormatCount(snapshot.TotalRepoCount);
        ForksText = FormatCount(snapshot.ForkCount);
        OrgsText = snapshot.Organizations.Count == 0
            ? App.Localize("Lbl_None")
            : string.Join(" · ", snapshot.Organizations);

        var rows = new List<GitHubRepoRow>(snapshot.RecentRepositories.Count);
        foreach (GitHubRepositoryInfo repo in snapshot.RecentRepositories)
        {
            var badges = new List<string>(2);
            if (repo.IsPrivate)
            {
                badges.Add(App.Localize("Lbl_PrivateBadge"));
            }

            if (repo.IsFork)
            {
                badges.Add(App.Localize("Lbl_ForkBadge"));
            }

            rows.Add(new GitHubRepoRow
            {
                Name = repo.Name,
                Badge = string.Join(" · ", badges),
                StarsText = repo.StarCount > 0 ? $"★ {repo.StarCount:N0}" : string.Empty,
            });
        }

        RecentRepositories = rows;
        RaiseAll();
    }
}

// -------------------------------------------------------------------------------------------
// MakerWorld card
// -------------------------------------------------------------------------------------------

/// <summary>Localized display row for one MakerWorld model.</summary>
public sealed class MakerWorldModelRow
{
    public string Title { get; init; } = string.Empty;
    public string StatsText { get; init; } = string.Empty;
}

public sealed class MakerWorldCardViewModel : ModuleCardViewModelBase
{
    private MakerWorldSnapshot? _snapshot;

    public string DisplayNameText { get; private set; } = string.Empty;
    public string HandleText { get; private set; } = string.Empty;
    public string FansText { get; private set; } = "—";
    public string FollowingText { get; private set; } = "—";
    public string LikesText { get; private set; } = "—";
    public string CollectionsText { get; private set; } = "—";
    public string DesignsText { get; private set; } = "—";
    public string DownloadsText { get; private set; } = "—";
    public string PrintsText { get; private set; } = "—";
    public IReadOnlyList<MakerWorldModelRow> Models { get; private set; } = Array.Empty<MakerWorldModelRow>();

    public void Apply(MakerWorldSnapshot snapshot)
    {
        _snapshot = snapshot;
        ApplySharedStatus(snapshot, "Status_Connected");
        UpdateRows();
    }

    public override void Relocalize()
    {
        ApplySharedStatus(_snapshot, "Status_Connected");
        UpdateRows();
    }

    private void UpdateRows()
    {
        var snapshot = _snapshot;
        if (snapshot is null)
        {
            return;
        }

        if (!snapshot.IsAvailable)
        {
            RaiseAll();
            return;
        }

        DisplayNameText = snapshot.DisplayName ?? "—";
        HandleText = snapshot.Handle ?? "—";
        FansText = FormatCount(snapshot.FanCount);
        FollowingText = FormatCount(snapshot.FollowCount);
        LikesText = FormatCount(snapshot.LikeCount);
        CollectionsText = FormatCount(snapshot.CollectionCount);
        DesignsText = FormatCount(snapshot.DesignCount);
        DownloadsText = FormatCount(snapshot.DesignDownloadCount);
        PrintsText = FormatCount(snapshot.DesignPrintCount);

        var rows = new List<MakerWorldModelRow>(snapshot.Models.Count);
        foreach (MakerWorldModelInfo model in snapshot.Models)
        {
            rows.Add(new MakerWorldModelRow
            {
                Title = model.Title,
                StatsText = App.LocalizeFormat(
                    "Lbl_ModelStats",
                    FormatCount(model.LikeCount),
                    FormatCount(model.DownloadCount),
                    FormatCount(model.PrintCount)),
            });
        }

        Models = rows;
        RaiseAll();
    }
}

// -------------------------------------------------------------------------------------------
// Weather (Nullschool earth map) card
// -------------------------------------------------------------------------------------------

/// <summary>
/// State of the weather card. The map itself is a WebView2 control owned by the WeatherCard view;
/// this view model only records availability so the card can swap between map and an explanatory
/// overlay. No weather service is polled on the 30 s timer — the WebView2 navigates on its own.
/// </summary>
public sealed class WeatherCardViewModel : ViewModelBase
{
    private bool _isAvailable;
    private string _statusLabel = string.Empty;
    private string _message = string.Empty;
    private Brush _statusBrush = Palette.Amber;
    private string _updatedText = string.Empty;
    private bool _isLoading = true;
    private string? _failedKey;
    private string? _failedDetail;

    public bool IsAvailable
    {
        get => _isAvailable;
        private set { _isAvailable = value; OnPropertyChanged(); }
    }

    public bool IsLoading
    {
        get => _isLoading;
        private set { _isLoading = value; OnPropertyChanged(); }
    }

    public string StatusLabel
    {
        get => _statusLabel;
        private set { _statusLabel = value; OnPropertyChanged(); }
    }

    public string Message
    {
        get => _message;
        private set { _message = value; OnPropertyChanged(); }
    }

    public Brush StatusBrush
    {
        get => _statusBrush;
        private set { _statusBrush = value; OnPropertyChanged(); }
    }

    public string UpdatedText
    {
        get => _updatedText;
        private set { _updatedText = value; OnPropertyChanged(); }
    }

    public void MarkLoading()
    {
        IsLoading = true;
        IsAvailable = false;
        StatusLabel = App.Localize("Status_Checking");
        StatusBrush = Palette.Amber;
        Message = App.Localize("Status_Checking");
        _failedKey = null;
        _failedDetail = null;
    }

    public void MarkAvailable()
    {
        IsLoading = false;
        IsAvailable = true;
        StatusLabel = App.Localize("Status_Available");
        StatusBrush = Palette.Mint;
        Message = string.Empty;
        UpdatedText = App.LocalizeFormat("Lbl_Updated", DateTime.Now.ToString("HH:mm:ss"));
        _failedKey = null;
        _failedDetail = null;
    }

    public void MarkFailed(string reasonKey, string? detail)
    {
        IsLoading = false;
        IsAvailable = false;
        StatusLabel = App.Localize("Status_Unavailable");
        StatusBrush = Palette.Gray;
        _failedKey = reasonKey;
        _failedDetail = detail;
        Message = App.LocalizeFormat(reasonKey, detail ?? string.Empty);
    }

    /// <summary>Recomputes localized strings after a language switch.</summary>
    public void Relocalize()
    {
        if (_isAvailable)
        {
            StatusLabel = App.Localize("Status_Available");
            UpdatedText = App.LocalizeFormat("Lbl_Updated", DateTime.Now.ToString("HH:mm:ss"));
            return;
        }

        if (_isLoading)
        {
            StatusLabel = App.Localize("Status_Checking");
            Message = App.Localize("Status_Checking");
            return;
        }

        StatusLabel = App.Localize("Status_Unavailable");
        if (!string.IsNullOrEmpty(_failedKey))
        {
            Message = string.IsNullOrEmpty(_failedDetail)
                ? App.Localize(_failedKey)
                : App.LocalizeFormat(_failedKey, _failedDetail);
        }
    }
}

// -------------------------------------------------------------------------------------------
// macOS-only modules (Harness, Codex, Command Code)
// -------------------------------------------------------------------------------------------

/// <summary>Card that always shows the Unavailable state with an explanatory message.</summary>
public sealed class UnavailableCardViewModel : ModuleCardViewModelBase
{
    private FailedSnapshot? _snapshot;

    public UnavailableCardViewModel(string reasonKey)
    {
        _snapshot = new FailedSnapshot(reasonKey);
        ApplySharedStatus(_snapshot, "Status_Unavailable");
    }

    /// <summary>Refreshes the "Updated" footer (the reason text never changes).</summary>
    public void Touch()
    {
        _snapshot = new FailedSnapshot(_snapshot?.ReasonKey ?? "Status_Unavailable");
        ApplySharedStatus(_snapshot, "Status_Unavailable");
    }

    public override void Relocalize() => ApplySharedStatus(_snapshot, "Status_Unavailable");
}

// -------------------------------------------------------------------------------------------
// Main view model
// -------------------------------------------------------------------------------------------

/// <summary>
/// Drives the whole dashboard. A single DispatcherTimer ticks once per second; every 30 ticks it
/// refreshes all data sources in parallel on background work while the UI stays responsive. Each
/// card exposes a child view model consumed by its UserControl.
/// </summary>
public sealed class MainViewModel : ViewModelBase, IDisposable
{
    public const int RefreshIntervalSeconds = 30;

    private readonly SystemMetricsService _systemService = new();
    private readonly GitHubService _gitHubService = new();
    private readonly MakerWorldService _makerWorldService = new();

    private readonly DispatcherTimer _timer;
    private int _secondsUntilRefresh = RefreshIntervalSeconds;
    private bool _isRefreshing;
    private bool _disposed;

    public MainViewModel()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += OnTimerTick;
    }

    // Card view models (DataContext of the seven UserControls in MainWindow).
    public SystemCardViewModel System { get; } = new();
    public GitHubCardViewModel GitHub { get; } = new();
    public MakerWorldCardViewModel MakerWorld { get; } = new();
    public WeatherCardViewModel Weather { get; } = new();
    public UnavailableCardViewModel Harness { get; } = new("Msg_MacOSOnly_Harness");
    public UnavailableCardViewModel Codex { get; } = new("Msg_MacOSOnly_Codex");
    public UnavailableCardViewModel CommandCode { get; } = new("Msg_MacOSOnly_CommandCode");

    // Toolbar state.
    public string RefreshCycleText { get; private set; } = string.Empty;
    public string LastRefreshText { get; private set; } = string.Empty;

    public void Start()
    {
        // Show immediate first results, then keep the 30 s cadence.
        _ = RefreshAllAsync();
        _timer.Start();
    }

    public void RefreshNow() => _ = RefreshAllAsync();

    /// <summary>User clicked the language toggle (the App reorders the dictionaries first).</summary>
    public void SwitchLanguage(string code)
    {
        if (string.Equals(App.LanguageCode, code, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        App.SetLanguage(code);
        // OnLanguageChanged() is invoked by App after the swap.
    }

    /// <summary>Called by App after the merged language dictionaries have been reordered.</summary>
    public void OnLanguageChanged()
    {
        System.Relocalize();
        GitHub.Relocalize();
        MakerWorld.Relocalize();
        Weather.Relocalize();
        Harness.Relocalize();
        Codex.Relocalize();
        CommandCode.Relocalize();
        UpdateToolbar();
    }

    private void OnTimerTick(object? sender, EventArgs e)
    {
        if (_isRefreshing)
        {
            UpdateToolbar();
            return;
        }

        _secondsUntilRefresh--;
        if (_secondsUntilRefresh <= 0)
        {
            _secondsUntilRefresh = RefreshIntervalSeconds;
            _ = RefreshAllAsync();
        }
        else
        {
            UpdateToolbar();
        }
    }

    private async Task RefreshAllAsync()
    {
        if (_isRefreshing)
        {
            return;
        }

        _isRefreshing = true;
        UpdateToolbar();

        string makerWorldUserId = SettingsService.Current.MakerWorldUserId;
        var cancellation = CancellationToken.None;

        try
        {
            // Kick off all sources at once; each service enforces its own timeout so a dead
            // network can never freeze the dashboard.
            Task<SystemMetricsSnapshot> systemTask = Task.Run(() => _systemService.Sample(), cancellation);
            Task<GitHubSnapshot> gitHubTask = _gitHubService.SampleAsync(cancellation);
            Task<MakerWorldSnapshot> makerWorldTask = _makerWorldService.SampleAsync(makerWorldUserId, cancellation);

            try
            {
                System.Apply(await systemTask.ConfigureAwait(true));
            }
            catch (Exception)
            {
                System.Apply(new SystemMetricsSnapshot(DateTime.Now, null, 0, 0, 0, 0, Environment.ProcessorCount, "Windows", "Msg_SystemUnavailable"));
            }

            try
            {
                GitHub.Apply(await gitHubTask.ConfigureAwait(true));
            }
            catch (Exception)
            {
                GitHub.Apply(new GitHubSnapshot(DateTime.Now, false, null, null, null, null, null, Array.Empty<string>(), Array.Empty<GitHubRepositoryInfo>(), "Msg_GhCommandFailed", "unexpected error"));
            }

            try
            {
                MakerWorld.Apply(await makerWorldTask.ConfigureAwait(true));
            }
            catch (Exception)
            {
                MakerWorld.Apply(new MakerWorldSnapshot(DateTime.Now, false, null, null, null, null, null, null, null, null, null, Array.Empty<MakerWorldModelInfo>(), "Msg_NetworkError", "unexpected error"));
            }

            // The macOS-only modules re-evaluate on the same cadence (their answer never changes,
            // but the "Updated" footer should honestly reflect the last check time).
            Harness.Touch();
            Codex.Touch();
            CommandCode.Touch();
        }
        finally
        {
            _isRefreshing = false;
            _secondsUntilRefresh = RefreshIntervalSeconds;
            LastRefreshText = App.LocalizeFormat("Lbl_LastRefresh", DateTime.Now.ToString("HH:mm:ss"));
            UpdateToolbar();
        }
    }

    private void UpdateToolbar()
    {
        if (_isRefreshing)
        {
            RefreshCycleText = App.Localize("Lbl_Refreshing");
        }
        else
        {
            string auto = App.LocalizeFormat("Lbl_AutoRefresh", RefreshIntervalSeconds);
            string next = App.LocalizeFormat("Lbl_NextIn", Math.Max(0, _secondsUntilRefresh));
            RefreshCycleText = $"{auto} · {next}";
        }

        OnPropertyChanged(nameof(RefreshCycleText));
        OnPropertyChanged(nameof(LastRefreshText));
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _timer.Stop();
        _timer.Tick -= OnTimerTick;
    }
}
