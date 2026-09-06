using FusionWorkbench.Models;

namespace FusionWorkbench.Services;

/// <summary>
/// Provides the snapshots for the three modules whose data source only exists in the macOS build:
///   - Harness (reads ~/.dsh, the local DeepSeek Harness store maintained by the macOS desktop app)
///   - Codex (talks to the local Codex app-server binary in the macOS ChatGPT app)
///   - Command Code (runs the Command Code CLI shipped in the macOS Command Code app)
/// On Windows these always report Unavailable with an explanatory, localized message — they never
/// synthesize placeholder numbers.
/// </summary>
public static class UnavailableService
{
    public static FailedSnapshot Harness()
        => new("Msg_MacOSOnly_Harness", sampledAt: DateTime.Now);

    public static FailedSnapshot Codex()
        => new("Msg_MacOSOnly_Codex", sampledAt: DateTime.Now);

    public static FailedSnapshot CommandCode()
        => new("Msg_MacOSOnly_CommandCode", sampledAt: DateTime.Now);
}
