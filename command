/// <summary>TabaPay's webhook endpoint for final transaction status.</summary>
public string? TABAPAY_WEBHOOK_URL { get; set; }


"rtpSend:AppSettings:TABAPAY_WEBHOOK_URL": "https://<tabapay-webhook-endpoint>"

services.AddHttpClient<ITabaPayWebhookClient, TabaPayWebhookClient>();



using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using PaymentServices.RTPSend.Helpers;
using PaymentServices.RTPSend.Services;

namespace PaymentServices.RTPSend.Functions;

/// <summary>
/// Service Bus Trigger — drains the <c>tabapay-webhook</c> subscription on the
/// shared <c>payment-processing</c> topic (filtered to Subject =
/// 'CreatePayment - Success' / 'CreatePayment - Failure').
///
/// Those notifications are published by <see cref="HandlePaymentOutcome"/> and
/// <see cref="HandleTabaPayRetry"/> once a payment reaches a final state. This
/// function forwards each one to TabaPay's webhook endpoint, telling them the
/// final status of the transaction. The message body is posted as-is.
///
/// MANUAL SETTLE, consistent with the other consumers:
///   • delivered            → complete
///   • transient failure    → abandon (Service Bus redelivers; DLQ after
///                            maxDeliveryCount)
///   • terminal failure     → dead-letter (4xx / not configured — retrying
///                            cannot help, so don't burn deliveries)
/// </summary>
public sealed class HandleTabaPayWebhook
{
    private readonly ITabaPayWebhookClient _webhookClient;
    private readonly ILogger<HandleTabaPayWebhook> _logger;

    public HandleTabaPayWebhook(
        ITabaPayWebhookClient webhookClient,
        ILogger<HandleTabaPayWebhook> logger)
    {
        _webhookClient = webhookClient;
        _logger = logger;
    }

    [Function(nameof(HandleTabaPayWebhook))]
    public async Task RunAsync(
        [ServiceBusTrigger(
            topicName: "payment-processing",
            subscriptionName: "tabapay-webhook",
            Connection = "SERVICE_BUS_CONNSTRING")]
        ServiceBusReceivedMessage serviceBusMessage,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        var payload = serviceBusMessage.Body.ToString();
        var subject = serviceBusMessage.Subject;

        // evolveId is only pulled out for logging/correlation — the payload is
        // forwarded to TabaPay exactly as published.
        var evolveId = TryReadEvolveId(payload);

        _logger.LogInformation(
            "TabaPay webhook notification received. EvolveId={EvolveId} Subject={Subject} DeliveryCount={DeliveryCount}",
            evolveId, subject, serviceBusMessage.DeliveryCount);

        WebhookDeliveryResult result;
        try
        {
            result = await _webhookClient.SendAsync(payload, subject, evolveId, cancellationToken);
        }
        catch (Exception ex)
        {
            // The client swallows its own failures, so anything here is unexpected.
            _logger.LogError(ex,
                "Unexpected error delivering TabaPay webhook. EvolveId={EvolveId}; abandoning.", evolveId);
            await TabaPaySendFlow.AbandonAsync(messageActions, serviceBusMessage, _logger, evolveId, cancellationToken);
            return;
        }

        if (result.Success)
        {
            await TabaPaySendFlow.CompleteAsync(messageActions, serviceBusMessage, _logger, evolveId, cancellationToken);
            return;
        }

        if (result.IsRetryable)
        {
            _logger.LogWarning(
                "TabaPay webhook delivery failed (retryable) for EvolveId={EvolveId}; abandoning for redelivery. {Detail}",
                evolveId, result.Detail);
            await TabaPaySendFlow.AbandonAsync(messageActions, serviceBusMessage, _logger, evolveId, cancellationToken);
            return;
        }

        _logger.LogError(
            "TabaPay webhook delivery failed (terminal) for EvolveId={EvolveId}; dead-lettering. {Detail}",
            evolveId, result.Detail);
        await TabaPaySendFlow.DeadLetterAsync(
            messageActions, serviceBusMessage, _logger,
            "TabaPayWebhookFailed", result.Detail ?? "Webhook delivery failed", evolveId, cancellationToken);
    }

    /// <summary>
    /// Best-effort extraction of evolveId from the envelope for logging only.
    /// Never throws — the payload is forwarded regardless.
    /// </summary>
    private static string? TryReadEvolveId(string payload)
    {
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(payload);
            return doc.RootElement.TryGetProperty("evolveId", out var value)
                ? value.GetString()
                : null;
        }
        catch
        {
            return null;
        }
    }
}





using System.Text;
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

    /// <summary>Transient (5xx / timeout / transport) — worth redelivering.</summary>
    public static WebhookDeliveryResult Retryable(string detail) => new(false, true, detail);

    /// <summary>Terminal (4xx / not configured) — retrying won't help.</summary>
    public static WebhookDeliveryResult Terminal(string detail) => new(false, false, detail);
}

/// <summary>
/// Typed HttpClient for TabaPay's transaction-status webhook. Mirrors the
/// GatewayClient pattern: a single config-driven URL.
/// </summary>
public sealed class TabaPayWebhookClient : ITabaPayWebhookClient
{
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

        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json")
        };

        _logger.LogInformation(
            "Calling TabaPay webhook. EvolveId={EvolveId} Subject={Subject}", evolveId, subject);

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, cancellationToken);
        }
        catch (Exception ex)
        {
            // Transport failure — transient, worth redelivering.
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

        // 4xx (except 408/429) means the payload/endpoint is wrong — retrying
        // won't change the outcome, so treat it as terminal and dead-letter.
        var isRetryable = status is 408 or 429 || status >= 500;

        _logger.LogError(
            "TabaPay webhook returned {StatusCode} ({Disposition}). EvolveId={EvolveId} Body={Body}",
            status, isRetryable ? "retryable" : "terminal", evolveId, body);

        return isRetryable
            ? WebhookDeliveryResult.Retryable($"HTTP {status}: {body}")
            : WebhookDeliveryResult.Terminal($"HTTP {status}: {body}");
    }
}
