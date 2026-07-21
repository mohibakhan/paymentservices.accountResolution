using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaymentServices.RTPSend.Constants;
using PaymentServices.RTPSend.Exceptions;
using PaymentServices.RTPSend.Helpers;
using PaymentServices.RTPSend.Interface.Adapters;
using PaymentServices.RTPSend.Interface.Services;
using PaymentServices.RTPSend.Models.Cosmos;
using PaymentServices.RTPSend.Models.Domain;
using PaymentServices.RTPSend.Models.Request;
using PaymentServices.RTPSend.Models.Response;
using PaymentServices.RTPSend.Settings;

namespace PaymentServices.RTPSend.Services;

/// <summary>
/// Single responsibility: POST to TabaPay, patch the Cosmos document with the
/// outcome, return a <see cref="TabaPaySendResult"/>.
/// </summary>
public sealed class TabaPaySendService : ITabaPaySendService
{
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    private readonly ILogger<TabaPaySendService> _logger;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly RtpSendSettings _settings;
    private readonly IPaymentCosmosDBAdapter _paymentCosmosDB;

    public TabaPaySendService(
        ILogger<TabaPaySendService> logger,
        IHttpClientFactory httpClientFactory,
        IOptions<RtpSendSettings> settings,
        IPaymentCosmosDBAdapter paymentCosmosDB)
    {
        _logger = logger;
        _httpClientFactory = httpClientFactory;
        _settings = settings.Value;
        _paymentCosmosDB = paymentCosmosDB;
    }

    public async Task<TabaPaySendResult> ProcessPayment(EvolvePaymentRequest cosmosPaymentItem)
    {
        var tabapayRequest = TabaPayRequestHelper.ConvertEvolveToTabaPayRequest(
            cosmosPaymentItem,
            _settings.TABAPAY_SOURCE_ACCOUNT_ID);

        // Tag every line emitted during this call — including the resilience
        // handler's retry logs — with the correlation keys, so a single payment
        // is traceable end-to-end even when many run concurrently.
        using var scope = _logger.BeginScope(new Dictionary<string, object>
        {
            ["EvolveId"] = cosmosPaymentItem.EvolveId,
            ["ReferenceId"] = tabapayRequest.ReferenceId
        });

        _logger.LogInformation("TabaPay processing for evolveId {EvolveId}", cosmosPaymentItem.EvolveId);

        HttpResponseMessage httpResponse;
        string rawBody;
        var stopwatch = Stopwatch.StartNew();

        try
        {
            httpResponse = await SendTransactionAsync(tabapayRequest);
            rawBody = await httpResponse.Content.ReadAsStringAsync();
            stopwatch.Stop();

            // Full body at Debug only — it can carry account numbers / PII.
            _logger.LogDebug("TabaPay raw response ({Status}) in {ElapsedMs}ms: {Body}",
                httpResponse.StatusCode, stopwatch.ElapsedMilliseconds, rawBody);
        }
        catch (HttpRequestException ex)
        {
            // Transport-level failure (DNS, connection reset, etc.) — transient, worth retrying.
            stopwatch.Stop();
            _logger.LogError(ex, "TabaPay HTTP call failed after {ElapsedMs}ms: {Message}",
                stopwatch.ElapsedMilliseconds, ex.Message);

            var failedDoc = await PatchTransactionStatusAsync(
                RequestStage.TABAPAY, RequestStatus.FAILED, $"HTTP error: {ex.Message}", cosmosPaymentItem);

            // Hand the post-patch document to the caller — its own copy still reads
            // COMPLETED from the LEDGER stage.
            throw new TabaPayProcessingException($"TabaPay HTTP call failed: {ex.Message}", ex, isRetryable: true)
            {
                Document = failedDoc ?? cosmosPaymentItem
            };
        }
        catch (TaskCanceledException ex)
        {
            // Timeout — transient, worth retrying.
            stopwatch.Stop();
            _logger.LogError(ex, "TabaPay HTTP call timed out after {ElapsedMs}ms.", stopwatch.ElapsedMilliseconds);

            var timedOutDoc = await PatchTransactionStatusAsync(
                RequestStage.TABAPAY, RequestStatus.FAILED, "Timeout calling TabaPay", cosmosPaymentItem);

            throw new TabaPayProcessingException("TabaPay HTTP call timed out", ex, isRetryable: true)
            {
                Document = timedOutDoc ?? cosmosPaymentItem
            };
        }

        var responseContentType = httpResponse.Content.Headers.ContentType?.ToString();

        var tabaPayResponse = TryDeserialize(rawBody);
        var isSuccess =
            (int)httpResponse.StatusCode == (int)HttpStatusCode.OK
            && tabaPayResponse?.Status == PaymentRequestConstants.TabaPayComplete
            && tabaPayResponse.Sc == (int)HttpStatusCode.OK;

        // Transient (retry): 5xx server faults, plus 429 (rate limited) and 408
        // (request timeout) that survived the in-call resilience retries — those
        // clear on their own given time. Deterministic failures (other 4xx like a
        // bad softDescriptor, or an HTTP-200 business decline) fail identically on
        // every retry, so they're terminal and get a distinct status.
        var statusCode = (int)httpResponse.StatusCode;
        var isRetryable = !isSuccess &&
            (statusCode >= 500
             || statusCode == (int)HttpStatusCode.TooManyRequests   // 429
             || statusCode == (int)HttpStatusCode.RequestTimeout);  // 408

        var looksLikeEdgeRejection =
            !isSuccess &&
            tabaPayResponse is null &&
            responseContentType is not null &&
            !responseContentType.Contains("json", StringComparison.OrdinalIgnoreCase);

        var patchedDoc = await PatchTransactionStatusAsync(
            RequestStage.TABAPAY,
            isSuccess ? RequestStatus.COMPLETED
                      : isRetryable ? RequestStatus.FAILED
                                    : RequestStatus.FAILED_TABAPAY,
            rawBody,
            cosmosPaymentItem);

        if (!isSuccess)
        {
            if (looksLikeEdgeRejection)
            {
                // Body is not PII — it's an error page from an intermediary — so it's
                // safe to log in full here, and it's the only thing that identifies
                // which hop rejected the call.
                _logger.LogError(
                    "TabaPay rejected at the edge (non-JSON error page, likely proxy/APIM/WAF, not a decline) " +
                    "in {ElapsedMs}ms. HttpStatus={Status} ContentType={ContentType} Body={Body}",
                    stopwatch.ElapsedMilliseconds,
                    httpResponse.StatusCode,
                    responseContentType,
                    rawBody);
            }
            else
            {
                _logger.Log(
                    isRetryable ? LogLevel.Warning : LogLevel.Error,
                    "TabaPay non-success ({Retryability}) in {ElapsedMs}ms. " +
                    "HttpStatus={Status} ContentType={ContentType} SC={Sc} EC={Ec} NetworkRC={NetworkRc} TabaStatus={TabaStatus}",
                    isRetryable ? "retryable" : "terminal",
                    stopwatch.ElapsedMilliseconds,
                    httpResponse.StatusCode,
                    responseContentType,
                    tabaPayResponse?.Sc,
                    tabaPayResponse?.Ec,
                    tabaPayResponse?.NetworkRc,
                    tabaPayResponse?.Status);
            }

            throw new TabaPayProcessingException(
                $"TabaPay returned non-success. HTTP status: {httpResponse.StatusCode}. Response: {rawBody}",
                isRetryable: isRetryable,
                statusCode: httpResponse.StatusCode)
            {
                Document = patchedDoc ?? cosmosPaymentItem
            };
        }

        // Patch transaction IDs onto the Cosmos document. Build off the just-patched
        // doc, not the original — the original predates the TABAPAY/COMPLETED patch
        // (and carries a stale ETag if the adapter uses one as a precondition).
        var patched = await PatchTabaPayIdsAsync(
            tabaPayResponse!, tabapayRequest.ReferenceId, patchedDoc ?? cosmosPaymentItem);

        // Reconciliation keys for matching this payment against TabaPay's ledger.
        _logger.LogInformation(
            "TabaPay COMPLETED in {ElapsedMs}ms. TransactionId={TransactionId} Network={Network} " +
            "NetworkId={NetworkId} ApprovalCode={ApprovalCode}",
            stopwatch.ElapsedMilliseconds,
            tabaPayResponse!.TransactionId,
            tabaPayResponse.Network,
            tabaPayResponse.NetworkId,
            tabaPayResponse.ApprovalCode);

        return new TabaPaySendResult
        {
            Document = patched ?? patchedDoc ?? cosmosPaymentItem,
            Response = tabaPayResponse!,
            RawResponse = rawBody
        };
    }

    private async Task<HttpResponseMessage> SendTransactionAsync(TabapayPaymentRequest tabaPayRequest)
    {
        var client = _httpClientFactory.CreateClient(nameof(TabaPaySendService));

        var json = JsonSerializer.Serialize(tabaPayRequest, _jsonOptions);
        // Full request body at Debug only — contains account numbers / PII.
        _logger.LogDebug("TabaPay request body: {Body}", json);

        using var request = new HttpRequestMessage(HttpMethod.Post, _settings.TABAPAY_SEND_URL)
        {
            Content = new StringContent(json, Encoding.UTF8)
        };

        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");

        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        request.Headers.TryAddWithoutValidation("User-Agent", "PaymentServices.RTPSend/1.0");

        request.Headers.TryAddWithoutValidation("x-Client-Id", _settings.TABAPAY_SEND_CLIENT_ID);
        request.Headers.TryAddWithoutValidation("x-merchant-id", _settings.TABAPAY_SEND_MERCHANT_ID);
        request.Headers.TryAddWithoutValidation("Ocp-Apim-Subscription-Key", _settings.TABAPAY_SEND_APIKEY);

        return await client.SendAsync(request);
    }

    private static TabaPayResponse? TryDeserialize(string body)
    {
        if (string.IsNullOrWhiteSpace(body)) return null;
        try { return JsonSerializer.Deserialize<TabaPayResponse>(body, _jsonOptions); }
        catch (JsonException) { return null; }
    }

    private async Task<EvolvePaymentRequest?> PatchTabaPayIdsAsync(
        TabaPayResponse tabaPayResponse,
        string referenceId,
        EvolvePaymentRequest request)
    {
        var patches = EvolvePaymentRequestHelper.GetTabaPaypatchoperation(
            tabaPayResponse.TransactionId, referenceId, tabaPayResponse.NetworkId);
        return await _paymentCosmosDB.PatchItemAsync(request, patches);
    }

    private async Task<EvolvePaymentRequest?> PatchTransactionStatusAsync(
        RequestStage stage, RequestStatus status, string additionalInfo, EvolvePaymentRequest request)
    {
        var patches = EvolvePaymentRequestHelper.GetStatusPatchOperation(stage, status, additionalInfo);
        return await _paymentCosmosDB.PatchItemAsync(request, patches);
    }
}










using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaymentServices.RTPSend.Constants;
using PaymentServices.RTPSend.Exceptions;
using PaymentServices.RTPSend.Helpers;
using PaymentServices.RTPSend.Interface.Adapters;
using PaymentServices.RTPSend.Interface.Services;
using PaymentServices.RTPSend.Models;
using PaymentServices.RTPSend.Models.Cosmos;
using PaymentServices.RTPSend.Models.Domain;
using PaymentServices.RTPSend.Services;
using PaymentServices.RTPSend.Settings;
using PaymentServices.Shared.Enums;
using PaymentServices.Shared.Infrastructure;
using PaymentServices.Shared.Messages;
using System.Text.Json;

namespace PaymentServices.RTPSend.Functions;

/// <summary>
/// Subscribed to the rtpsend-outcome subscription on the shared
/// payment-processing topic. Filter matches:
///   TransferCompleted, TransferFailed, AccountResolutionFailed.
///
/// On TransferCompleted → load the RTPSend payment doc and call TabaPay.
/// On TransferFailed / AccountResolutionFailed → mark the payment terminally
/// failed (FAILED, or FAILED_NSF when the failure reason indicates NSF).
///
/// Transfer reports its per-stage progress via boolean flags on the outcome
/// message (LimitPassed / ScreeningPassed / LedgerPosted), which become granular
/// LIMIT/SCREENING/LEDGER statusHistory entries on the paymentRequests doc.
///
/// Transfer also reports the LEDGER ENTRY POINTER (LedgerEntryId + LedgerId) on
/// the outcome message. Persist on payment doc so it is available in
/// every downstream path — including TabaPay retries, which run off the retry
/// queue and have no PaymentMessage
/// call to tptch/status endpoint, which uses it to point-
/// update the ledger entry's status once the TabaPay outcome is final.
///
/// MANUAL SETTLE: this function takes explicit control of the Service Bus
/// message via ServiceBusMessageActions (Complete / Abandon / DeadLetter)
/// instead of relying on auto-complete.
/// </summary>
public class HandlePaymentOutcome
{
    private const int MaxLookupDeliveryAttempts = 5;

    private readonly IPaymentCosmosDBAdapter _paymentCosmosDB;
    private readonly ITabaPaySendService _tabaPay;
    private readonly IServiceBusMessageService _serviceBus;
    private readonly ITransferStatusClient _transferStatus;
    private readonly RtpSendSettings _settings;
    private readonly ILogger<HandlePaymentOutcome> _logger;

    public HandlePaymentOutcome(
        IPaymentCosmosDBAdapter paymentCosmosDB,
        ITabaPaySendService tabaPay,
        IServiceBusMessageService serviceBus,
        ITransferStatusClient transferStatus,
        IOptions<RtpSendSettings> settings,
        ILogger<HandlePaymentOutcome> logger)
    {
        _paymentCosmosDB = paymentCosmosDB;
        _tabaPay = tabaPay;
        _serviceBus = serviceBus;
        _transferStatus = transferStatus;
        _settings = settings.Value;
        _logger = logger;
    }

    [Function(nameof(HandlePaymentOutcome))]
    public async Task Run(
        [ServiceBusTrigger(
            topicName: "payment-processing",
            subscriptionName: "rtpsend-outcome",
            Connection = "SERVICE_BUS_CONNSTRING")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        PaymentMessage? outcome;
        try
        {
            outcome = ServiceBusPublisher.Deserialize(message);
        }
        catch (Exception ex)
        {
            // Unparseable — no point retrying. Dead-letter explicitly.
            _logger.LogError(ex,
                "Cannot deserialize outcome message {MessageId}; dead-lettering.",
                message.MessageId);
            await SafeDeadLetterAsync(messageActions, message,
                "DeserializeError", ex.Message, message.MessageId, cancellationToken);
            return;
        }

        _logger.LogInformation(
            "Outcome received. EvolveId={EvolveId} State={State} DeliveryCount={DeliveryCount}",
            outcome.EvolveId, outcome.State, message.DeliveryCount);

        try
        {
            switch (outcome.State)
            {
                case TransactionState.TransferCompleted:
                    await HandleSuccessAsync(outcome, message, messageActions, cancellationToken);
                    break;

                case TransactionState.TransferFailed:
                case TransactionState.AccountResolutionFailed:
                    await HandleFailureAsync(outcome, message, messageActions, cancellationToken);
                    break;

                default:
                    // Filter shouldn't deliver anything else; complete so it
                    // doesn't loop.
                    _logger.LogWarning(
                        "Ignoring unexpected outcome state {State} for evolveId {EvolveId}.",
                        outcome.State, outcome.EvolveId);
                    await SafeCompleteAsync(messageActions, message, outcome.EvolveId, cancellationToken);
                    break;
            }
        }
        catch (Exception ex)
        {
            // Unexpected — abandon for redelivery; SB will DLQ after maxDeliveryCount.
            _logger.LogError(ex,
                "Unexpected error handling outcome for evolveId {EvolveId}; abandoning.",
                outcome.EvolveId);
            await SafeAbandonAsync(messageActions, message, outcome.EvolveId, cancellationToken);
        }
    }

    private async Task HandleSuccessAsync(
        PaymentMessage outcome,
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        var payment = await LookupPaymentAsync(outcome.EvolveId);

        if (payment is null)
        {
            // The doc should exist (ProcessPayment wrote it). Abandon so a later
            // delivery finds it — unless we've tried enough times, in which case
            // dead-letter for investigation.
            await HandleMissingDocAsync(outcome, message, messageActions, cancellationToken);
            return;
        }

        var lastStatusEntry = payment.StatusHistory?.LastOrDefault();
        var hasTerminalCompletedStatus = payment.Status == RequestStatus.COMPLETED.ToString()
            && lastStatusEntry?.Stage == RequestStage.TABAPAY.ToString()
            && lastStatusEntry?.Status == RequestStatus.COMPLETED.ToString();

        // Idempotency — if TabaPay already completed for this doc, don't repeat.
        if (hasTerminalCompletedStatus)
        {
            _logger.LogInformation(
                "Payment {EvolveId} already COMPLETED; completing message.", outcome.EvolveId);
            await SafeCompleteAsync(messageActions, message, outcome.EvolveId, cancellationToken);
            return;
        }

        // Persist the ledger entry pointer (id + partition key) from Transfer onto
        // the payment doc.
        payment = await PersistLedgerPointerAsync(payment, outcome);

        // TransferCompleted means LIMIT, SCREENING and LEDGER all passed in
        // Transfer. Record each as its own COMPLETED history entry (authoritative
        // — Transfer owns these stages) before calling TabaPay.
        payment = await WriteStageHistoryAsync(payment, outcome, isFailure: false);

        _logger.LogInformation(
            "Limit, screening and ledger passed; calling TabaPay for {EvolveId}.", outcome.EvolveId);

        TabaPaySendResult sendResult;
        try
        {
            sendResult = await _tabaPay.ProcessPayment(payment);
        }
        catch (TabaPayProcessingException ex)
        {
            // ProcessPayment patched the doc to FAILED / FAILED_TABAPAY before
            // throwing. Our `payment` is the pre-call object, whose Status still
            // reads COMPLETED from the LEDGER stage — take the post-failure doc off
            // the exception so the notification envelope and the tptch/status
            // callback report the real state.
            payment = ex.Document ?? payment;

            // First attempt (attempt 0). Non-retryable → notify + dead-letter now;
            // retryable → schedule a backed-off retry. Both TERMINAL branches also
            // report FAILED to Transfer's tptch/status (which updates the ledger
            // entry). No instant abandon/redelivery loop.
            await TabaPaySendFlow.HandleFailureAsync(
                _serviceBus, _transferStatus, _logger, _settings.MaxTabaPayRetries,
                payment, ex, attempt: 0, message, messageActions, cancellationToken);
            return;
        }

        _logger.LogInformation("Payment {EvolveId} COMPLETED via TabaPay.", outcome.EvolveId);

        // Report the final outcome to Transfer, which point-updates the ledger
        // entry's status. Best-effort — never throws (the payment is settled).
        await _transferStatus.ReportStatusAsync(
            payment.EvolveId,
            TransferStatusClient.CompletedStatus,
            payment.LedgerEntryId,
            payment.LedgerId,
            cancellationToken);

        // Best-effort downstream notification
        await TabaPaySendFlow.PublishSuccessNotificationAsync(
            _serviceBus, _logger, sendResult.Document, sendResult.Response);

        // Work done — settle explicitly.
        await SafeCompleteAsync(messageActions, message, outcome.EvolveId, cancellationToken);
    }

    private async Task HandleFailureAsync(
        PaymentMessage outcome,
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        var payment = await LookupPaymentAsync(outcome.EvolveId);

        if (payment is null)
        {
            await HandleMissingDocAsync(outcome, message, messageActions, cancellationToken);
            return;
        }

        // NSF surfaces as a terminal, distinct status; everything else FAILED.
        var isNsf = outcome.FailureReason is not null &&
                    outcome.FailureReason.Contains("insufficient", StringComparison.OrdinalIgnoreCase);

        var terminalStatus = isNsf ? RequestStatus.FAILED_NSF : RequestStatus.FAILED;

        EvolvePaymentRequest patched;

        if (outcome.State == TransactionState.AccountResolutionFailed)
        {
            // Failed at account resolution — BEFORE Transfer ran, so none of the
            // LIMIT/SCREENING/LEDGER flags are set. Don't run the per-stage helper
            // (it would mislabel this as a LIMIT failure). Write a single
            // ACCOUNTLOOKUP/FAILED entry instead.
            var resolutionPatch = EvolvePaymentRequestHelper.GetStatusPatchOperation(
                RequestStage.ACCOUNTLOOKUP,
                terminalStatus,
                additionalInfo: new
                {
                    Message = $"Pipeline failure: {outcome.State}",
                    Reason = outcome.FailureReason
                });

            patched = await _paymentCosmosDB.PatchItemAsync(payment, resolutionPatch) ?? payment;
        }
        else
        {
            // TransferFailed — Transfer ran, so use the per-stage flags: COMPLETED
            // for each stage that passed, FAILED (or FAILED_NSF at the ledger) for
            // the first stage that did not. WriteStageHistoryAsync's FAILED patch
            // ALSO sets the doc-level Status/Stage (GetStatusPatchOperation does
            // both), so no separate terminal patch is needed.
            //
            // NOTE: no tptch/status callback here. A TransferFailed means Transfer
            // itself failed (limit/screening/NSF) — the ledger debit either never
            // happened or Transfer already handled it. There is no ledger entry of
            // ours to mark FAILED. The callback only concerns the TabaPay outcome.
            patched = await WriteStageHistoryAsync(payment, outcome, isFailure: true, isNsf: isNsf);
        }

        _logger.LogWarning(
            "Payment {EvolveId} marked {Status} ({State}): {Reason}",
            outcome.EvolveId, terminalStatus, outcome.State, outcome.FailureReason);

        await PublishNotificationAsync(
            patched,
            success: false,
            subject: PaymentRequestConstants.FailureServiceBusSubject,
            tabaPayResponse: null,
            comments: outcome.FailureReason ?? $"Pipeline failure: {outcome.State}");

        await SafeCompleteAsync(messageActions, message, outcome.EvolveId, cancellationToken);
    }

    /// <summary>
    /// Persists the ledger entry pointer (LedgerEntryId + LedgerId) that Transfer
    /// put on the outcome message onto the payment document, so it survives into
    /// the retry path (which has no PaymentMessage) and is durable for later
    /// reconciliation. No-op if Transfer didn't supply it or it's already stored.
    /// </summary>
    private async Task<EvolvePaymentRequest> PersistLedgerPointerAsync(
        EvolvePaymentRequest payment,
        PaymentMessage outcome)
    {
        if (string.IsNullOrWhiteSpace(outcome.LedgerEntryId) ||
            string.IsNullOrWhiteSpace(outcome.LedgerId))
        {
            _logger.LogWarning(
                "Outcome carried no ledger entry pointer for {EvolveId}; tptch/status " +
                "callback will be skipped.", outcome.EvolveId);
            return payment;
        }

        // Already persisted (e.g. a redelivery) — nothing to do.
        if (payment.LedgerEntryId == outcome.LedgerEntryId &&
            payment.LedgerId == outcome.LedgerId)
        {
            return payment;
        }

        var patches = new List<PatchOperation>
        {
            PatchOperation.Set("/ledgerEntryId", outcome.LedgerEntryId),
            PatchOperation.Set("/ledgerId", outcome.LedgerId)
        };

        var patched = await _paymentCosmosDB.PatchItemAsync(payment, patches) ?? payment;

        _logger.LogInformation(
            "Persisted ledger pointer. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId} LedgerId={LedgerId}",
            outcome.EvolveId, outcome.LedgerEntryId, outcome.LedgerId);

        return patched;
    }

    /// <summary>
    /// Turns Transfer's per-stage progress flags (LimitPassed / ScreeningPassed /
    /// LedgerPosted) into statusHistory entries:
    ///   - each passed stage → &lt;STAGE&gt; / COMPLETED
    ///   - on a failure, the FIRST not-passed stage → &lt;STAGE&gt; / FAILED
    ///     (FAILED_NSF when the failure is NSF at the ledger)
    /// Stops at the first not-passed stage (nothing after it ran).
    /// </summary>
    private async Task<EvolvePaymentRequest> WriteStageHistoryAsync(
        EvolvePaymentRequest payment,
        PaymentMessage outcome,
        bool isFailure,
        bool isNsf = false)
    {
        var stages = new (bool Passed, RequestStage Stage)[]
        {
            (outcome.LimitPassed,     RequestStage.LIMIT),
            (outcome.ScreeningPassed, RequestStage.SCREENING),
            (outcome.LedgerPosted,    RequestStage.LEDGER)
        };

        foreach (var (passed, stage) in stages)
        {
            if (passed)
            {
                var completedPatch = EvolvePaymentRequestHelper.GetStatusPatchOperation(
                    stage,
                    RequestStatus.COMPLETED,
                    additionalInfo: new { Message = $"{stage} passed" });

                payment = await _paymentCosmosDB.PatchItemAsync(payment, completedPatch) ?? payment;
                continue;
            }

            // First not-passed stage. On a failure, record which stage failed.
            if (isFailure)
            {
                // NSF happens at the ledger debit → label that stage FAILED_NSF.
                var stageStatus = (isNsf && stage == RequestStage.LEDGER)
                    ? RequestStatus.FAILED_NSF
                    : RequestStatus.FAILED;

                var failedPatch = EvolvePaymentRequestHelper.GetStatusPatchOperation(
                    stage,
                    stageStatus,
                    additionalInfo: new
                    {
                        Message = $"{stage} failed",
                        Reason = outcome.FailureReason
                    });

                payment = await _paymentCosmosDB.PatchItemAsync(payment, failedPatch) ?? payment;
            }

            // Nothing after the first not-passed stage ran.
            break;
        }

        return payment;
    }

    /// <summary>
    /// Loads the RTPSend payment document by evolveId. The doc's id != evolveId
    /// (the ctor generates them independently) and the container is partitioned
    /// by /evolveId, so this is a query (FindAllItemsAsync), not a point read.
    /// </summary>
    private async Task<EvolvePaymentRequest?> LookupPaymentAsync(string evolveId)
        => (await _paymentCosmosDB.FindAllItemsAsync(evolveId)).FirstOrDefault();

    /// <summary>
    /// Doc not found. Abandon to force redelivery so a later attempt finds it.
    /// Only after MaxLookupDeliveryAttempts do we dead-letter, so we never
    /// silently drop the message — important because the ledger has already been
    /// debited at this point.
    /// </summary>
    private async Task HandleMissingDocAsync(
        PaymentMessage outcome,
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        if (message.DeliveryCount < MaxLookupDeliveryAttempts)
        {
            _logger.LogWarning(
                "Payment doc not yet found for evolveId {EvolveId} (DeliveryCount={DeliveryCount}); " +
                "abandoning for redelivery (read-your-own-write race).",
                outcome.EvolveId, message.DeliveryCount);
            await SafeAbandonAsync(messageActions, message, outcome.EvolveId, cancellationToken);
        }
        else
        {
            _logger.LogError(
                "Payment doc still not found for evolveId {EvolveId} after {Attempts} attempts; " +
                "dead-lettering (ledger may have been debited — needs reconciliation).",
                outcome.EvolveId, message.DeliveryCount);
            await SafeDeadLetterAsync(messageActions, message,
                "PaymentDocNotFound",
                $"No RTPSend payment doc for evolveId {outcome.EvolveId} after {message.DeliveryCount} attempts",
                outcome.EvolveId, cancellationToken);
        }
    }

    // Notification + settle live in TabaPaySendFlow

    private Task PublishNotificationAsync(
        EvolvePaymentRequest payment,
        bool success,
        string subject,
        Models.Response.TabaPayResponse? tabaPayResponse,
        string? comments) =>
        TabaPaySendFlow.PublishNotificationAsync(
            _serviceBus, _logger, payment, success, subject, tabaPayResponse, comments);

    private Task SafeCompleteAsync(
        ServiceBusMessageActions actions, ServiceBusReceivedMessage msg,
        string? evolveId, CancellationToken ct) =>
        TabaPaySendFlow.CompleteAsync(actions, msg, _logger, evolveId, ct);

    private Task SafeAbandonAsync(
        ServiceBusMessageActions actions, ServiceBusReceivedMessage msg,
        string? evolveId, CancellationToken ct) =>
        TabaPaySendFlow.AbandonAsync(actions, msg, _logger, evolveId, ct);

    private Task SafeDeadLetterAsync(
        ServiceBusMessageActions actions, ServiceBusReceivedMessage msg,
        string reason, string description, string? evolveId, CancellationToken ct) =>
        TabaPaySendFlow.DeadLetterAsync(actions, msg, _logger, reason, description, evolveId, ct);
}
