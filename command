using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaymentServices.RTPSend.Settings;

namespace PaymentServices.RTPSend.Services;

public interface ITabaPayWebhookClient
{
    /// <summary>
    /// POSTs the notification envelope to TabaPay's webhook endpoint, telling
    /// them the final status of a transaction. Returns the outcome so the caller
    /// can decide how to settle the Service Bus message.
    /// </summary>
    Task<WebhookDeliveryResult> SendAsync(
        string payload, string? subject, string? evolveId, CancellationToken cancellationToken = default);
}

/// <summary>Outcome of a webhook delivery attempt.</summary>
public sealed record WebhookDeliveryResult(bool Success, bool IsRetryable, string? Detail)
{
    public static WebhookDeliveryResult Ok() => new(true, false, null);

    /// <summary>Transient (5xx / 408 / 429 / transport) — worth redelivering.</summary>
    public static WebhookDeliveryResult Retryable(string detail) => new(false, true, detail);

    /// <summary>Terminal (other 4xx / not configured) — retrying won't help.</summary>
    public static WebhookDeliveryResult Terminal(string detail) => new(false, false, detail);
}

/// <summary>
/// Typed HttpClient for TabaPay's transaction-status webhook. Mirrors the
/// GatewayClient pattern (config-driven URL) and uses the same authentication
/// headers as TabaPaySendService: x-Client-Id / x-merchant-id /
/// Ocp-Apim-Subscription-Key.
/// </summary>
public sealed class TabaPayWebhookClient : ITabaPayWebhookClient
{
    /// <summary>Matches "(" or ")" anywhere in the string.</summary>
    private static readonly Regex _parenthesis = new(@"[()]", RegexOptions.Compiled);

    /// <summary>
    /// Matches an embedded JSON object — the raw TabaPay error body that gets
    /// concatenated into the exception message and lands in "comments".
    /// </summary>
    private static readonly Regex _embeddedJson = new(@"\{[^{}]*\}", RegexOptions.Compiled);

    /// <summary>Quotes and braces that survive after the JSON strip.</summary>
    private static readonly Regex _structuralChars = new(@"[{}\[\]""]", RegexOptions.Compiled);

    /// <summary>Collapses runs of whitespace left behind after stripping.</summary>
    private static readonly Regex _repeatedWhitespace = new(@"\s{2,}", RegexOptions.Compiled);

    private readonly HttpClient _httpClient;
    private readonly RtpSendSettings _settings;
    private readonly ILogger<TabaPayWebhookClient> _logger;

    public TabaPayWebhookClient(
        HttpClient httpClient,
        IOptions<RtpSendSettings> settings,
        ILogger<TabaPayWebhookClient> logger)
    {
        _httpClient = httpClient;
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task<WebhookDeliveryResult> SendAsync(
        string payload, string? subject, string? evolveId, CancellationToken cancellationToken = default)
    {
        var url = _settings.TABAPAY_WEBHOOK_URL;

        if (string.IsNullOrWhiteSpace(url))
        {
            _logger.LogWarning(
                "TABAPAY_WEBHOOK_URL is not configured; cannot deliver webhook. EvolveId={EvolveId}", evolveId);
            return WebhookDeliveryResult.Terminal("TABAPAY_WEBHOOK_URL is not configured");
        }

        // TabaPay's endpoint rejects parentheses and embedded JSON in "comments",
        // so clean it before delivery. The Cosmos document keeps the original text.
        payload = SanitiseComments(payload, evolveId);

        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(payload, Encoding.UTF8)
        };

        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");

        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        request.Headers.TryAddWithoutValidation("User-Agent", "PaymentServices.RTPSend/1.0");

        // Same auth as the TabaPay send call.
        request.Headers.TryAddWithoutValidation("x-Client-Id", _settings.TABAPAY_SEND_CLIENT_ID);
        request.Headers.TryAddWithoutValidation("x-merchant-id", _settings.TABAPAY_SEND_MERCHANT_ID);
        request.Headers.TryAddWithoutValidation("Ocp-Apim-Subscription-Key", _settings.TABAPAY_SEND_APIKEY);

        _logger.LogInformation(
            "Calling TabaPay webhook. EvolveId={EvolveId} Subject={Subject}", evolveId, subject);

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, cancellationToken);
        }
        catch (Exception ex)
        {
            // Transport failure — transient.
            _logger.LogError(ex,
                "TabaPay webhook call failed (transport). EvolveId={EvolveId}", evolveId);
            return WebhookDeliveryResult.Retryable($"Transport failure: {ex.Message}");
        }

        if (response.IsSuccessStatusCode)
        {
            _logger.LogInformation(
                "TabaPay webhook accepted. EvolveId={EvolveId} StatusCode={StatusCode}",
                evolveId, (int)response.StatusCode);
            return WebhookDeliveryResult.Ok();
        }

        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        var status = (int)response.StatusCode;
        var responseContentType = response.Content.Headers.ContentType?.ToString();

        var isRetryable = status >= 500 || status == 429 || status == 408;

        // An HTML body on a 4xx usually means a proxy/WAF rejected us, not the app.
        var looksLikeEdgeRejection =
            !isRetryable &&
            responseContentType is not null &&
            responseContentType.Contains("text/html", StringComparison.OrdinalIgnoreCase);

        if (looksLikeEdgeRejection)
        {
            _logger.LogError(
                "TabaPay webhook rejected at the edge (HTML error page, likely proxy/WAF, not payload). " +
                "EvolveId={EvolveId} StatusCode={StatusCode} ContentType={ContentType} Body={Body}",
                evolveId, status, responseContentType, body);
        }
        else
        {
            _logger.LogError(
                "TabaPay webhook returned {StatusCode} ({Disposition}). EvolveId={EvolveId} ContentType={ContentType} Body={Body}",
                status, isRetryable ? "retryable" : "terminal", evolveId, responseContentType, body);
        }

        return isRetryable
            ? WebhookDeliveryResult.Retryable($"HTTP {status}: {body}")
            : WebhookDeliveryResult.Terminal($"HTTP {status}: {body}");
    }

    /// <summary>
    /// Cleans the top-level "comments" field and returns the re-serialized
    /// envelope. Two problems are handled:
    ///
    ///   1. Embedded JSON — TabaPaySendService concatenates TabaPay's raw error
    ///      body into the exception message, which becomes "comments". That
    ///      produces escaped quotes and braces nested inside a string value.
    ///      The object is replaced with its EM/EC values where present, so the
    ///      diagnostic survives without the structural characters.
    ///   2. Parentheses — the endpoint rejects them outright.
    ///
    /// If the payload doesn't parse, or has no comments value, or nothing needs
    /// changing, the original string is returned untouched — sanitising must
    /// never be the reason a delivery fails.
    /// </summary>
    private string SanitiseComments(string payload, string? evolveId)
    {
        try
        {
            if (JsonNode.Parse(payload) is not JsonObject root)
                return payload;

            if (root["comments"]?.GetValue<string>() is not string comments ||
                comments.Length == 0)
                return payload;

            var cleaned = CleanCommentText(comments);

            if (string.Equals(cleaned, comments, StringComparison.Ordinal))
                return payload;

            root["comments"] = cleaned;

            _logger.LogDebug(
                "Sanitised webhook comments. EvolveId={EvolveId} Original={Original} Cleaned={Cleaned}",
                evolveId, comments, cleaned);

            return root.ToJsonString();
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException)
        {
            // Malformed payload, or "comments" wasn't a string. Send as-is and let
            // the endpoint decide — sanitising is best-effort, not a gate.
            _logger.LogWarning(ex,
                "Could not sanitise webhook comments; sending payload unmodified. EvolveId={EvolveId}", evolveId);
            return payload;
        }
    }

    /// <summary>
    /// Flattens embedded JSON to readable key=value text, then strips remaining
    /// structural characters and parentheses.
    /// </summary>
    private static string CleanCommentText(string comments)
    {
        // Replace each embedded JSON object with a flattened, quote-free rendering
        // of its fields: {"SC":400,"EC":"3C5E1961"} -> SC=400 EC=3C5E1961
        var flattened = _embeddedJson.Replace(comments, match =>
        {
            var inner = match.Value;

            try
            {
                if (JsonNode.Parse(inner) is JsonObject obj)
                {
                    var parts = obj
                        .Where(kv => kv.Value is not null)
                        .Select(kv => $"{kv.Key}={kv.Value!.ToString()}");

                    return string.Join(" ", parts);
                }
            }
            catch (JsonException)
            {
                // Not valid JSON after all — fall through to the blunt strip below.
            }

            return _structuralChars.Replace(inner, string.Empty);
        });

        // Anything structural that survived (unbalanced braces, stray quotes).
        var stripped = _structuralChars.Replace(flattened, string.Empty);

        // Parentheses are rejected by the endpoint regardless of context.
        stripped = _parenthesis.Replace(stripped, string.Empty);

        return _repeatedWhitespace.Replace(stripped, " ").Trim();
    }
}
