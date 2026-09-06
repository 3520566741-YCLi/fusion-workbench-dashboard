using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using FusionWorkbench.Models;

namespace FusionWorkbench.Services;

/// <summary>One GitHub repository row, mirroring macOS GitHubRepositoryInfo.</summary>
public sealed class GitHubRepositoryInfo
{
    public string Name { get; init; } = string.Empty;
    public bool IsPrivate { get; init; }
    public bool IsFork { get; init; }
    public string? Language { get; init; }
    public int StarCount { get; init; }
    public DateTime? UpdatedAt { get; init; }
}

/// <summary>One GitHub status sample, mirroring macOS GitHubStatusSnapshot.</summary>
public sealed class GitHubSnapshot : ModuleSnapshot
{
    public GitHubSnapshot(
        DateTime sampledAt,
        bool isAvailable,
        string? username,
        DateTime? accountCreatedAt,
        int? publicRepoCount,
        int? privateRepoCount,
        int? forkCount,
        IReadOnlyList<string> organizations,
        IReadOnlyList<GitHubRepositoryInfo> recentRepositories,
        string? reasonKey = null,
        string? reasonDetail = null)
        : base(sampledAt, isAvailable, reasonKey, reasonDetail)
    {
        Username = username;
        AccountCreatedAt = accountCreatedAt;
        PublicRepoCount = publicRepoCount;
        PrivateRepoCount = privateRepoCount;
        ForkCount = forkCount;
        Organizations = organizations;
        RecentRepositories = recentRepositories;
    }

    public string? Username { get; }
    public DateTime? AccountCreatedAt { get; }
    public int? PublicRepoCount { get; }
    public int? PrivateRepoCount { get; }
    public int? ForkCount { get; }
    public IReadOnlyList<string> Organizations { get; }
    public IReadOnlyList<GitHubRepositoryInfo> RecentRepositories { get; }

    public int? TotalRepoCount =>
        PublicRepoCount.HasValue && PrivateRepoCount.HasValue ? PublicRepoCount + PrivateRepoCount : null;
}

/// <summary>
/// GitHub data source for Windows: shells out to the GitHub CLI (gh), exactly like the macOS
/// GitHubStatusSampler. It queries:
///   gh api user
///   gh api user/repos?per_page=100&amp;affiliation=owner
///   gh api user/orgs
/// and parses the JSON with System.Text.Json. No REST token path is implemented (keep it simple:
/// gh only, as specified). When gh is missing or not authenticated, the card reports Unavailable
/// with an install/sign-in hint — it never shows fake counts.
/// </summary>
public sealed class GitHubService
{
    private const string GhExecutable = "gh";
    private static readonly TimeSpan CommandTimeout = TimeSpan.FromSeconds(15);

    public async Task<GitHubSnapshot> SampleAsync(CancellationToken cancellationToken)
    {
        DateTime sampledAt = DateTime.Now;

        // Running "gh api user" also exercises PATH lookup: a Win32Exception means gh is absent.
        (int exitCode, string stdout, string stderr) user;
        try
        {
            user = await ProcessRunner.RunAsync(
                GhExecutable,
                new[] { "api", "user" },
                CommandTimeout,
                cancellationToken).ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            return GitHubFailure("Msg_Timeout");
        }
        catch (Win32Exception)
        {
            return GitHubFailure("Msg_GhNotFound");
        }
        catch (OperationCanceledException)
        {
            return GitHubFailure("Msg_Timeout");
        }

        if (user.ExitCode != 0)
        {
            return GitHubFailureFromGhError(user.StdErr + user.StdOut);
        }

        GhUser? ghUser = Deserialize<GhUser>(user.StdOut);
        if (ghUser is null || string.IsNullOrWhiteSpace(ghUser.Login))
        {
            return GitHubFailure("Msg_GhNotAuthenticated");
        }

        // Repos and orgs are best-effort, mirroring the macOS sampler (only the user is required).
        var repos = await FetchRepositoriesAsync(cancellationToken);
        var organizations = await FetchOrganizationsAsync(cancellationToken);

        var recent = repos
            .OrderByDescending(r => r.UpdatedAt ?? DateTime.MinValue)
            .Take(4)
            .ToList();

        return new GitHubSnapshot(
            sampledAt,
            isAvailable: true,
            username: ghUser.Login,
            accountCreatedAt: ghUser.CreatedAt,
            publicRepoCount: ghUser.PublicRepos,
            privateRepoCount: repos.Count(r => r.IsPrivate),
            forkCount: repos.Count(r => r.IsFork),
            organizations: organizations,
            recentRepositories: recent);
    }

    private async Task<List<GitHubRepositoryInfo>> FetchRepositoriesAsync(CancellationToken cancellationToken)
    {
        try
        {
            (int exitCode, string stdout, string _) = await ProcessRunner.RunAsync(
                GhExecutable,
                new[] { "api", "user/repos?per_page=100&affiliation=owner" },
                CommandTimeout,
                cancellationToken).ConfigureAwait(false);

            if (exitCode != 0)
            {
                return new List<GitHubRepositoryInfo>();
            }

            var dtos = JsonSerializer.Deserialize<List<GhRepo>>(stdout);
            if (dtos is null)
            {
                return new List<GitHubRepositoryInfo>();
            }

            return dtos.Select(d => new GitHubRepositoryInfo
            {
                Name = d.Name ?? string.Empty,
                IsPrivate = d.IsPrivate,
                IsFork = d.IsFork,
                Language = d.Language,
                StarCount = d.StarCount,
                UpdatedAt = d.UpdatedAt,
            }).ToList();
        }
        catch (Exception)
        {
            // Best effort only, like the macOS sampler returning an empty list on failure.
            return new List<GitHubRepositoryInfo>();
        }
    }

    private async Task<List<string>> FetchOrganizationsAsync(CancellationToken cancellationToken)
    {
        try
        {
            (int exitCode, string stdout, string _) = await ProcessRunner.RunAsync(
                GhExecutable,
                new[] { "api", "user/orgs" },
                CommandTimeout,
                cancellationToken).ConfigureAwait(false);

            if (exitCode != 0)
            {
                return new List<string>();
            }

            var dtos = JsonSerializer.Deserialize<List<GhOrg>>(stdout);
            return dtos?
                .Select(o => o.Login)
                .Where(login => !string.IsNullOrWhiteSpace(login))
                .ToList() ?? new List<string>();
        }
        catch (Exception)
        {
            return new List<string>();
        }
    }

    private static GitHubSnapshot GitHubFailure(string reasonKey, string? detail = null)
        => new(DateTime.Now, false, null, null, null, null, null, Array.Empty<string>(), Array.Empty<GitHubRepositoryInfo>(), reasonKey, detail);

    private static GitHubSnapshot GitHubFailureFromGhError(string errorText)
    {
        string combined = string.IsNullOrWhiteSpace(errorText) ? string.Empty : errorText.Trim();
        if (combined.Contains("auth login", StringComparison.OrdinalIgnoreCase)
            || combined.Contains("401", StringComparison.Ordinal))
        {
            return GitHubFailure("Msg_GhNotAuthenticated");
        }

        string detail = FirstMeaningfulLine(combined);
        return GitHubFailure("Msg_GhCommandFailed", string.IsNullOrEmpty(detail) ? "unknown error" : detail);
    }

    private static string FirstMeaningfulLine(string text)
    {
        foreach (string rawLine in text.Split('\n'))
        {
            string line = rawLine.Trim();
            if (line.Length > 0)
            {
                return line.Length <= 300 ? line : line[..300];
            }
        }

        return string.Empty;
    }

    private static T? Deserialize<T>(string json)
        where T : class
    {
        try
        {
            return string.IsNullOrWhiteSpace(json) ? null : JsonSerializer.Deserialize<T>(json);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    // ---- gh JSON shapes (case-insensitive JSON property names) -----------------------------

    private sealed class GhUser
    {
        [JsonPropertyName("login")] public string? Login { get; set; }
        [JsonPropertyName("created_at")] public DateTime? CreatedAt { get; set; }
        [JsonPropertyName("public_repos")] public int PublicRepos { get; set; }
    }

    private sealed class GhRepo
    {
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("private")] public bool IsPrivate { get; set; }
        [JsonPropertyName("fork")] public bool IsFork { get; set; }
        [JsonPropertyName("language")] public string? Language { get; set; }
        [JsonPropertyName("stargazers_count")] public int StarCount { get; set; }
        [JsonPropertyName("updated_at")] public DateTime? UpdatedAt { get; set; }
    }

    private sealed class GhOrg
    {
        [JsonPropertyName("login")] public string? Login { get; set; }
    }
}
