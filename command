[JsonPropertyName("ledgerEntryId")]
public string? LedgerEntryId { get; set; }

[JsonPropertyName("ledgerId")]
public string? LedgerId { get; set; }


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
/// the outcome message. We PERSIST it on the payment doc so it is available in
/// every downstream path — including TabaPay retries, which run off the retry
/// queue and have no PaymentMessage — and so it is durable for reconciliation.
/// It is sent back to Transfer's tptch/status endpoint, which uses it to point-
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
        // the payment doc. This makes it available to EVERY later path — including
        // TabaPay retries, which run off the retry queue with no PaymentMessage —
        // and keeps it durable for reconciliation.
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





using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using PaymentServices.RTPSend.Constants;
using PaymentServices.RTPSend.Exceptions;
using PaymentServices.RTPSend.Interface.Services;
using PaymentServices.RTPSend.Models;
using PaymentServices.RTPSend.Models.Cosmos;
using PaymentServices.RTPSend.Models.Response;
using PaymentServices.RTPSend.Services;

namespace PaymentServices.RTPSend.Helpers;

/// <summary>
/// Shared settle/notify/retry logic for the TabaPay send step, used by both
/// <c>HandlePaymentOutcome</c> (first attempt, off the outcome message) and
/// <c>HandleTabaPayRetry</c> (backed-off retries, off the retry queue).
///
///   • non-retryable (4xx / hard decline) → notify + dead-letter immediately.
///   • retryable (5xx / timeout / network) → schedule a backed-off retry until
///     MaxTabaPayRetries is hit, then dead-letter. Never an instant abandon loop.
///
/// Both TERMINAL outcomes (non-retryable, and retries-exhausted) also report
/// "FAILED" to Transfer's tptch/status endpoint, which point-updates the ledger
/// entry's status. The pointer (LedgerEntryId + LedgerId) is read off the payment
/// document — HandlePaymentOutcome persists it there precisely so it is available
/// on the retry path, which has no PaymentMessage.
///
/// A scheduled retry is NOT terminal, so it does not report FAILED — the payment
/// is still in flight and may yet succeed.
/// </summary>
public static class TabaPaySendFlow
{
    /// <summary>Capped exponential backoff for the Nth (1-based) retry attempt.</summary>
    public static TimeSpan Backoff(int attempt) => attempt switch
    {
        <= 1 => TimeSpan.FromSeconds(30),
        2 => TimeSpan.FromMinutes(2),
        3 => TimeSpan.FromMinutes(5),
        4 => TimeSpan.FromMinutes(15),
        _ => TimeSpan.FromMinutes(30),
    };

    /// <summary>
    /// Disposes of a failed TabaPay send: notify + dead-letter when terminal, or
    /// schedule the next backed-off retry and complete the current message.
    /// <paramref name="attempt"/> is the attempt that just failed (0 = first try
    /// off the outcome message; N = the Nth retry off the retry queue).
    /// </summary>
    public static async Task HandleFailureAsync(
        IServiceBusMessageService serviceBus,
        ITransferStatusClient transferStatus,
        ILogger logger,
        int maxRetries,
        EvolvePaymentRequest payment,
        TabaPayProcessingException ex,
        int attempt,
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions actions,
        CancellationToken ct)
    {
        // ---- TERMINAL: non-retryable (hard decline / 4xx) --------------------
        if (!ex.IsRetryable)
        {
            logger.LogWarning(ex,
                "TabaPay non-retryable failure for {EvolveId} (status {Status}); notifying + dead-lettering.",
                payment.EvolveId, ex.StatusCode);

            await ReportTerminalFailureAsync(transferStatus, logger, payment, ct);
            await PublishFailureNotificationAsync(serviceBus, logger, payment, ex.Message);
            await DeadLetterAsync(actions, message, logger, "TabaPayNonRetryable", ex.Message, payment.EvolveId, ct);
            return;
        }

        // ---- TERMINAL: retries exhausted -------------------------------------
        var nextAttempt = attempt + 1;
        if (nextAttempt > maxRetries)
        {
            logger.LogError(ex,
                "TabaPay still failing for {EvolveId} after {Attempts} retries; dead-lettering.",
                payment.EvolveId, attempt);

            await ReportTerminalFailureAsync(transferStatus, logger, payment, ct);
            await PublishFailureNotificationAsync(serviceBus, logger, payment,
                $"TabaPay transient failure, retries exhausted: {ex.Message}");
            await DeadLetterAsync(actions, message, logger, "TabaPayRetriesExhausted", ex.Message, payment.EvolveId, ct);
            return;
        }

        // ---- NOT terminal: schedule a backed-off retry -----------------------
        // Do NOT report FAILED here — the payment is still being retried.
        var delay = Backoff(nextAttempt);
        await serviceBus.SendToQueueAsync(
            new TabaPayRetryMessage { EvolveId = payment.EvolveId, Attempt = nextAttempt },
            PaymentRequestConstants.ServiceBusTopicName,
            subject: PaymentRequestConstants.TabaPaySendRetrySubject,
            delay: delay);

        logger.LogWarning(ex,
            "TabaPay transient failure for {EvolveId}; scheduled retry {Attempt}/{Max} in {Delay}.",
            payment.EvolveId, nextAttempt, maxRetries, delay);

        await CompleteAsync(actions, message, logger, payment.EvolveId, ct);
    }

    /// <summary>
    /// Tells Transfer the payment has TERMINALLY failed, so it can mark the source
    /// debit's ledger entry FAILED. Uses the ledger pointer persisted on the
    /// payment doc. Best-effort — the client never throws.
    /// </summary>
    private static Task ReportTerminalFailureAsync(
        ITransferStatusClient transferStatus,
        ILogger logger,
        EvolvePaymentRequest payment,
        CancellationToken ct) =>
        transferStatus.ReportStatusAsync(
            payment.EvolveId,
            TransferStatusClient.FailedStatus,
            payment.LedgerEntryId,
            payment.LedgerId,
            ct);

    public static async Task PublishSuccessNotificationAsync(
        IServiceBusMessageService serviceBus, ILogger logger,
        EvolvePaymentRequest payment, TabaPayResponse? tabaPayResponse) =>
        await PublishNotificationAsync(serviceBus, logger, payment, success: true,
            PaymentRequestConstants.SuccessServiceBusSubject, tabaPayResponse, "Payment completed via TabaPay");

    public static Task PublishFailureNotificationAsync(
        IServiceBusMessageService serviceBus, ILogger logger,
        EvolvePaymentRequest payment, string? comments) =>
        PublishNotificationAsync(serviceBus, logger, payment, success: false,
            PaymentRequestConstants.FailureServiceBusSubject, tabaPayResponse: null, comments);

    /// <summary>Best-effort downstream notification — failures are logged, not thrown.</summary>
    public static async Task PublishNotificationAsync(
        IServiceBusMessageService serviceBus,
        ILogger logger,
        EvolvePaymentRequest payment,
        bool success,
        string subject,
        TabaPayResponse? tabaPayResponse,
        string? comments)
    {
        try
        {
            var envelope = ServiceBusHelper.CreateServiceBusMessage(
                payment,
                success: success,
                additionalInfo: new
                {
                    payment.PaymentReference,
                    Status = payment.Status
                },
                comments: comments);

            if (tabaPayResponse is not null)
                envelope.TabaPayResponse = tabaPayResponse;

            await serviceBus.SendMessageToServiceBusAsync(envelope, subject);

            logger.LogInformation(
                "Published '{Subject}' notification for EvolveId={EvolveId}.",
                subject, payment.EvolveId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex,
                "Failed to publish '{Subject}' notification for EvolveId={EvolveId}. " +
                "Payment is settled; notification will need manual replay.",
                subject, payment.EvolveId);
        }
    }

    // ---- Settle helpers (swallow settle errors so they don't cascade) -------

    public static async Task CompleteAsync(
        ServiceBusMessageActions actions, ServiceBusReceivedMessage msg, ILogger logger,
        string? evolveId, CancellationToken ct)
    {
        try { await actions.CompleteMessageAsync(msg, ct); }
        catch (Exception ex)
        {
            logger.LogWarning(ex,
                "CompleteMessage failed (likely lock lost) for EvolveId={EvolveId}.", evolveId ?? "unknown");
        }
    }

    public static async Task AbandonAsync(
        ServiceBusMessageActions actions, ServiceBusReceivedMessage msg, ILogger logger,
        string? evolveId, CancellationToken ct)
    {
        try { await actions.AbandonMessageAsync(msg, cancellationToken: ct); }
        catch (Exception ex)
        {
            logger.LogWarning(ex,
                "AbandonMessage failed (likely lock lost) for EvolveId={EvolveId}.", evolveId ?? "unknown");
        }
    }

    public static async Task DeadLetterAsync(
        ServiceBusMessageActions actions, ServiceBusReceivedMessage msg, ILogger logger,
        string reason, string description, string? evolveId, CancellationToken ct)
    {
        try
        {
            await actions.DeadLetterMessageAsync(msg,
                deadLetterReason: reason, deadLetterErrorDescription: description, cancellationToken: ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex,
                "DeadLetter failed (likely lock lost) for EvolveId={EvolveId}.", evolveId ?? "unknown");
        }
    }
}
