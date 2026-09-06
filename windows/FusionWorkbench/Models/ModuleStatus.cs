namespace FusionWorkbench.Models;

/// <summary>
/// Availability phase of a dashboard module. Cards show an "Available" body only when the
/// underlying data source answered with real data; every other path renders the Unavailable
/// state with an explanatory message. No fake/synthesized numbers are ever shown.
/// </summary>
public enum ModuleAvailability
{
    Available,
    Unavailable,
}

/// <summary>
/// Base class for every card snapshot. A snapshot either carries real, freshly sampled data
/// (<see cref="IsAvailable"/> == true) or an unavailable marker with a localization resource key
/// (<see cref="ReasonKey"/>, e.g. "Msg_GhNotFound") plus an optional dynamic detail argument
/// (e.g. the failing HTTP status code) that is substituted into the localized message.
/// </summary>
public abstract class ModuleSnapshot
{
    protected ModuleSnapshot(DateTime sampledAt, bool isAvailable, string? reasonKey = null, string? reasonDetail = null)
    {
        SampledAt = sampledAt;
        IsAvailable = isAvailable;
        ReasonKey = reasonKey;
        ReasonDetail = reasonDetail;
    }

    public DateTime SampledAt { get; }

    public bool IsAvailable { get; }

    public ModuleAvailability Availability => IsAvailable ? ModuleAvailability.Available : ModuleAvailability.Unavailable;

    /// <summary>Resource key of the localized reason; null when the snapshot is available.</summary>
    public string? ReasonKey { get; }

    /// <summary>Optional argument substituted into the localized reason template.</summary>
    public string? ReasonDetail { get; }
}

/// <summary>
/// A snapshot that only carries the unavailable reason (used by the macOS-only modules:
/// Harness, Codex, Command Code).
/// </summary>
public sealed class FailedSnapshot : ModuleSnapshot
{
    public FailedSnapshot(string reasonKey, string? reasonDetail = null, DateTime? sampledAt = null)
        : base(sampledAt ?? DateTime.Now, false, reasonKey, reasonDetail)
    {
    }
}
