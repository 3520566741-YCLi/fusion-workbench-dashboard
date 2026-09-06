using System.Net;
using System.Net.Http;
using System.Text.Json;
using FusionWorkbench.Models;

namespace FusionWorkbench.Services;

/// <summary>One MakerWorld model row, mirroring macOS MakerWorldModelInfo.</summary>
public sealed class MakerWorldModelInfo
{
    public long DesignId { get; init; }
    public string Title { get; init; } = string.Empty;
    public long LikeCount { get; init; }
    public long DownloadCount { get; init; }
    public long PrintCount { get; init; }
    public long CommentCount { get; init; }
    public long CollectionCount { get; init; }
    public DateTime? UpdatedAt { get; init; }
}

/// <summary>One MakerWorld status sample, mirroring macOS MakerWorldStatusSnapshot.</summary>
public sealed class MakerWorldSnapshot : ModuleSnapshot
{
    public MakerWorldSnapshot(
        DateTime sampledAt,
        bool isAvailable,
        string? handle,
        string? displayName,
        long? fanCount,
        long? followCount,
        long? likeCount,
        long? collectionCount,
        long? designCount,
        long? designDownloadCount,
        long? designPrintCount,
        IReadOnlyList<MakerWorldModelInfo> models,
        string? reasonKey = null,
        string? reasonDetail = null)
        : base(sampledAt, isAvailable, reasonKey, reasonDetail)
    {
        Handle = handle;
        DisplayName = displayName;
        FanCount = fanCount;
        FollowCount = followCount;
        LikeCount = likeCount;
        CollectionCount = collectionCount;
        DesignCount = designCount;
        DesignDownloadCount = designDownloadCount;
        DesignPrintCount = designPrintCount;
        Models = models;
    }

    public string? Handle { get; }
    public string? DisplayName { get; }
    public long? FanCount { get; }
    public long? FollowCount { get; }
    public long? LikeCount { get; }
    public long? CollectionCount { get; }
    public long? DesignCount { get; }
    public long? DesignDownloadCount { get; }
    public long? DesignPrintCount { get; }
    public IReadOnlyList<MakerWorldModelInfo> Models { get; }
}

/// <summary>
/// MakerWorld data source for Windows. Mirrors the API shape of the macOS MakerWorldStatusSampler:
///   GET https://api.bambulab.com/v1/design-user-service/user/profile/{userId}
///   GET https://api.bambulab.com/v1/design-service/design/{designId}?trafficSource=browse
/// The user id comes from Settings (SettingsService) and is never compiled into the binary.
/// Per-model detail fetches are capped at four designs so the 30 s refresh stays responsive.
/// Every failure path reports Unavailable with an explicit reason; no numbers are synthesized.
/// </summary>
public sealed class MakerWorldService
{
    private const string BaseUrl = "https://api.bambulab.com/v1";
    private const int MaxDesignDetailFetches = 4;
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(15);

    private static readonly HttpClient Http = CreateHttpClient();

    private static HttpClient CreateHttpClient()
    {
        var handler = new HttpClientHandler { AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate };
        return new HttpClient(handler) { Timeout = RequestTimeout };
    }

    public async Task<MakerWorldSnapshot> SampleAsync(string? userId, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return Unavailable("Msg_ConfigureMakerWorldId");
        }

        if (!long.TryParse(userId.Trim(), out long numericUserId) || numericUserId <= 0)
        {
            return Unavailable("Msg_InvalidMakerWorldId");
        }

        DateTime sampledAt = DateTime.Now;

        JsonFetchResult profileResult = await FetchJsonAsync(
            $"/design-user-service/user/profile/{numericUserId}",
            cancellationToken).ConfigureAwait(false);

        if (!profileResult.Succeeded || profileResult.Value is null)
        {
            return Unavailable(profileResult.ReasonKey ?? "Msg_Timeout", profileResult.ReasonDetail);
        }

        JsonElement root = profileResult.Value.Value;

        // The Bambu Lab API occasionally wraps responses in { "code":.., "message":.., "data": {..} }.
        // macOS treated the root as the profile; we defensively unwrap such a "data" payload when
        // the root itself does not look like a profile object.
        JsonElement profileObject = LooksLikeProfile(root) ? root : ReadData(root);

        var handle = ReadString(profileObject, "handle");
        var displayName = ReadString(profileObject, "name");
        long? fanCount = ReadInt64(profileObject, "fanCount");
        long? followCount = ReadInt64(profileObject, "followCount");
        long? likeCount = ReadInt64(profileObject, "likeCount");
        long? collectionCount = ReadInt64(profileObject, "collectionCount");

        // The model list and aggregate counters live under "personal"/"MWCount".
        JsonElement? personal = ReadObject(profileObject, "personal");
        JsonElement? mwCount = ReadObject(profileObject, "MWCount");
        long? designCount = ReadInt64(mwCount, "designCount");
        long? designDownloadCount = ReadInt64(mwCount, "myDesignDownloadCount");
        long? designPrintCount = ReadInt64(mwCount, "myDesignPrintCount");

        var models = new List<MakerWorldModelInfo>();
        foreach (long designId in ReadDesignIds(personal).Take(MaxDesignDetailFetches))
        {
            MakerWorldModelInfo? model = await FetchDesignAsync(designId, cancellationToken).ConfigureAwait(false);
            if (model is not null)
            {
                models.Add(model);
            }
        }

        return new MakerWorldSnapshot(
            sampledAt,
            isAvailable: true,
            handle: handle,
            displayName: displayName,
            fanCount: fanCount,
            followCount: followCount,
            likeCount: likeCount,
            collectionCount: collectionCount,
            designCount: designCount,
            designDownloadCount: designDownloadCount,
            designPrintCount: designPrintCount,
            models: models);
    }

    private static bool LooksLikeProfile(JsonElement root) => root.ValueKind == JsonValueKind.Object
        && (root.TryGetProperty("handle", out _)
            || root.TryGetProperty("name", out _)
            || root.TryGetProperty("personal", out _));

    private static JsonElement ReadData(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Object
            && root.TryGetProperty("data", out JsonElement data)
            && data.ValueKind == JsonValueKind.Object)
        {
            return data;
        }

        return root;
    }

    private static IEnumerable<long> ReadDesignIds(JsonElement? personal)
    {
        if (personal is null)
        {
            yield break;
        }

        JsonElement? designsInfo = ReadArray(personal.Value, "designsInfo");
        if (designsInfo is null)
        {
            yield break;
        }

        var seen = new HashSet<long>();
        foreach (JsonElement entry in designsInfo.Value.EnumerateArray())
        {
            if (ReadInt64(entry, "id") is long id && seen.Add(id))
            {
                yield return id;
            }
        }
    }

    private async Task<MakerWorldModelInfo?> FetchDesignAsync(long designId, CancellationToken cancellationToken)
    {
        JsonFetchResult result = await FetchJsonAsync(
            $"/design-service/design/{designId}?trafficSource=browse",
            cancellationToken).ConfigureAwait(false);

        if (!result.Succeeded || result.Value is null)
        {
            // Mirror the macOS sampler: a failing per-design fetch is skipped, not fatal.
            return null;
        }

        JsonElement design = result.Value.Value;
        // The design endpoint also uses the { data: {...} } envelope on occasion.
        if (!design.TryGetProperty("title", out _) && design.TryGetProperty("data", out JsonElement data))
        {
            design = data;
        }

        return new MakerWorldModelInfo
        {
            DesignId = designId,
            Title = ReadString(design, "title") ?? string.Empty,
            LikeCount = ReadInt64(design, "likeCount") ?? 0,
            DownloadCount = ReadInt64(design, "downloadCount") ?? 0,
            PrintCount = ReadInt64(design, "printCount") ?? 0,
            CommentCount = ReadInt64(design, "commentCount") ?? 0,
            CollectionCount = ReadInt64(design, "collectionCount") ?? 0,
            UpdatedAt = ReadInt64(design, "updateTime") is long unixSeconds
                ? DateTimeOffset.FromUnixTimeSeconds(unixSeconds).LocalDateTime
                : null,
        };
    }

    private static async Task<JsonFetchResult> FetchJsonAsync(string path, CancellationToken cancellationToken)
    {
        try
        {
            string url = BaseUrl + path;
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            // The MakerWorld endpoint expects a browser-like User-Agent (mirrors the macOS code).
            request.Headers.TryAddWithoutValidation(
                "User-Agent",
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36");

            using HttpResponseMessage response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);

            if (!response.IsSuccessStatusCode)
            {
                return JsonFetchResult.Fail("Msg_HttpError", ((int)response.StatusCode).ToString());
            }

            await using System.IO.Stream stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
            return JsonFetchResult.Ok(document.RootElement.Clone());
        }
        catch (OperationCanceledException)
        {
            // Either our cancellation token or the HttpClient timeout fired.
            return JsonFetchResult.Fail("Msg_Timeout");
        }
        catch (HttpRequestException ex)
        {
            return JsonFetchResult.Fail("Msg_NetworkError", ShortMessage(ex.Message));
        }
        catch (JsonException)
        {
            return JsonFetchResult.Fail("Msg_NetworkError", "unexpected response");
        }
    }

    private static string ShortMessage(string? message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return "connection failed";
        }

        string trimmed = message.Trim();
        return trimmed.Length <= 200 ? trimmed : trimmed[..200];
    }

    private static MakerWorldSnapshot Unavailable(string reasonKey, string? detail = null)
        => new(
            DateTime.Now,
            false,
            null, null, null, null, null, null, null, null, null,
            Array.Empty<MakerWorldModelInfo>(),
            reasonKey,
            detail);

    /// <summary>Outcome of one JSON GET, carrying the localized failure key on error.</summary>
    private sealed class JsonFetchResult
    {
        public bool Succeeded { get; init; }
        public JsonElement? Value { get; init; }
        public string? ReasonKey { get; init; }
        public string? ReasonDetail { get; init; }

        public static JsonFetchResult Ok(JsonElement value)
            => new() { Succeeded = true, Value = value };

        public static JsonFetchResult Fail(string reasonKey, string? reasonDetail = null)
            => new() { Succeeded = false, ReasonKey = reasonKey, ReasonDetail = reasonDetail };
    }

    // ---- Tiny System.Text.Json helpers (all accept a null parent and return null) ----------

    private static JsonElement? ReadObject(JsonElement? parent, string property)
    {
        if (parent is not JsonElement p || p.ValueKind != JsonValueKind.Object || !p.TryGetProperty(property, out JsonElement value))
        {
            return null;
        }

        return value.ValueKind == JsonValueKind.Object ? value : null;
    }

    private static JsonElement? ReadArray(JsonElement? parent, string property)
    {
        if (parent is not JsonElement p || p.ValueKind != JsonValueKind.Object || !p.TryGetProperty(property, out JsonElement value))
        {
            return null;
        }

        return value.ValueKind == JsonValueKind.Array ? value : null;
    }

    private static string? ReadString(JsonElement? parent, string property)
    {
        if (parent is not JsonElement p || p.ValueKind != JsonValueKind.Object || !p.TryGetProperty(property, out JsonElement value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.GetRawText(),
            _ => null,
        };
    }

    private static long? ReadInt64(JsonElement? parent, string property)
    {
        if (parent is not JsonElement p || p.ValueKind != JsonValueKind.Object || !p.TryGetProperty(property, out JsonElement value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetInt64(out long number) => number,
            JsonValueKind.String when long.TryParse(value.GetString(), out long parsed) => parsed,
            _ => null,
        };
    }
}
