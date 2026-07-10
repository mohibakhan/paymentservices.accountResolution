// =============================================================================
// Granular pipeline-stage history for HandlePaymentOutcome.
//
// Reads the 3 progress flags Transfer set on the outcome message
// (LimitPassed / ScreeningPassed / LedgerPosted) and writes matching
// statusHistory entries onto the RTPSend paymentRequests doc:
//   - each passed stage  -> <STAGE> / COMPLETED
//   - the first NOT-passed stage on a failure -> <STAGE> / FAILED (with reason)
//
// This REPLACES the single "Screening and limits passed" entry.
//
// Add this method to HandlePaymentOutcome and call it:
//   * in HandleSuccessAsync — after doc lookup + idempotency, before TabaPay:
//         payment = await WriteStageHistoryAsync(payment, outcome, isFailure: false);
//   * in HandleFailureAsync — after doc lookup, before the terminal FAILED patch
//     (or instead of a generic failure entry):
//         payment = await WriteStageHistoryAsync(payment, outcome, isFailure: true);
//
// Assumes RequestStage has LIMIT, SCREENING, LEDGER values (they already do).
// =============================================================================

private async Task<EvolvePaymentRequest> WriteStageHistoryAsync(
    EvolvePaymentRequest payment,
    PaymentMessage outcome,
    bool isFailure)
{
    // Ordered: (flag, stage). RTPSend writes COMPLETED for each true flag; on a
    // failure, the FIRST false flag is the stage that failed.
    var stages = new (bool Passed, RequestStage Stage)[]
    {
        (outcome.LimitPassed,     RequestStage.LIMIT),
        (outcome.ScreeningPassed, RequestStage.SCREENING),
        (outcome.LedgerPosted,    RequestStage.LEDGER)
    };

    var failedStageWritten = false;

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

        // First false flag. On a failure, this is the stage that failed — record
        // it once with the reason. On a success path we never hit a false flag
        // (all three are true), so this branch only matters for failures.
        if (isFailure && !failedStageWritten)
        {
            var failedPatch = EvolvePaymentRequestHelper.GetStatusPatchOperation(
                stage,
                RequestStatus.FAILED,
                additionalInfo: new
                {
                    Message = $"{stage} failed",
                    Reason = outcome.FailureReason
                });

            payment = await _paymentCosmosDB.PatchItemAsync(payment, failedPatch) ?? payment;
            failedStageWritten = true;
        }

        // Stop at the first non-passed stage — nothing after it ran.
        break;
    }

    return payment;
}


using Microsoft.Extensions.Logging;
using PaymentServices.Shared.Messages;
using PaymentServices.Transfer.Exceptions;
using PaymentServices.Transfer.Models;

namespace PaymentServices.Transfer.Services;

public interface ITransferService
{
    Task<TransferResult> ExecuteAsync(
        PaymentMessage message,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Runs the checks for a transfer:
///   1. LIMIT check
///   2. SCREENING check
///   3. LEDGER source debit via the Evolve NuGet (NSF terminal)
///
/// As each stage passes it sets the corresponding progress flag on the message
/// (LimitPassed / ScreeningPassed / LedgerPosted). Because these are set on the
/// message BEFORE any later stage can throw, a failure naturally carries the
/// flags for whatever passed first — so TransferFunction's failure path
/// publishes accurate partial progress, and RTPSend can render per-stage
/// history (COMPLETED for passed stages, FAILED for the one that threw).
///
/// Destination credit is intentionally NOT performed (source debit only).
/// </summary>
public sealed class TransferService : ITransferService
{
    private readonly ILimitService _limitService;
    private readonly IScreeningService _screeningService;
    private readonly ILedgerService _ledgerService;
    private readonly ILogger<TransferService> _logger;

    public TransferService(
        ILimitService limitService,
        IScreeningService screeningService,
        ILedgerService ledgerService,
        ILogger<TransferService> logger)
    {
        _limitService = limitService;
        _screeningService = screeningService;
        _ledgerService = ledgerService;
        _logger = logger;
    }

    public async Task<TransferResult> ExecuteAsync(
        PaymentMessage message,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Transfer executing. EvolveId={EvolveId} Amount={Amount} FintechId={FintechId}",
            message.EvolveId, message.Amount, message.FintechId);

        // ---- LIMIT --------------------------------------------------------
        var limit = await _limitService.CheckAsync(message, cancellationToken);
        if (!limit.Allowed)
        {
            throw new LimitExceededException(limit.Reason ?? "Limit check denied");
        }
        message.LimitPassed = true;

        // ---- SCREENING ----------------------------------------------------
        var screening = await _screeningService.CheckAsync(message, cancellationToken);
        if (!screening.Allowed)
        {
            throw new ScreeningRejectedException(screening.Reason ?? "Screening rejected");
        }
        message.ScreeningPassed = true;

        // ---- LEDGER (source debit) ---------------------------------------
        // NSF throws InsufficientFundsException (terminal). Other failures
        // return a Failed result which we turn into a retryable exception.
        var ledgerResult = await _ledgerService.ReserveAsync(new LedgerReservationRequest
        {
            EvolveId = message.EvolveId,
            FintechId = message.FintechId,
            CorrelationId = message.CorrelationId,
            FboAccountNumber = message.FboAccount ?? string.Empty,
            Amount = message.Amount
        }, cancellationToken);

        if (!ledgerResult.Success)
        {
            throw new InvalidOperationException(
                ledgerResult.Reason ?? "Ledger reservation failed");
        }
        message.LedgerPosted = true;

        _logger.LogInformation(
            "Transfer ledger debit complete. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId}",
            message.EvolveId, ledgerResult.ReservationId);

        return new TransferResult
        {
            GluIdSource = ledgerResult.ReservationId,
            GluIdDestination = null,           // source debit only
            EveTransactionId = message.EvolveId
        };
    }
}

/// <summary>Terminal — limit check denied the transfer.</summary>
public sealed class LimitExceededException : Exception
{
    public LimitExceededException(string message) : base(message) { }
}

/// <summary>Terminal — screening/compliance rejected the transfer.</summary>
public sealed class ScreeningRejectedException : Exception
{
    public ScreeningRejectedException(string message) : base(message) { }
}



using Azure.Messaging.ServiceBus;
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
using PaymentServices.RTPSend.Settings;
using PaymentServices.Shared.Enums;
using PaymentServices.Shared.Infrastructure;
using PaymentServices.Shared.Messages;
using System.Text.Json;

namespace PaymentServices.RTPSend.Functions;

/// <summary>
/// Subscribed to the rtpsend-outcome
/// subscription on the shared payment-processing topic. Filter matches:
///   TransferCompleted, TransferFailed, AccountResolutionFailed.
///
/// On TransferCompleted → load the RTPSend payment doc and call TabaPay.
/// On TransferFailed / AccountResolutionFailed → mark the payment terminally
/// failed (FAILED, or FAILED_NSF when the failure reason indicates NSF).
///
/// Transfer reports its per-stage progress via boolean flags on the outcome
/// message (LimitPassed / ScreeningPassed / LedgerPosted). This function turns
/// those into granular LIMIT/SCREENING/LEDGER statusHistory entries on the
/// paymentRequests doc — COMPLETED for each passed stage, and FAILED (with the
/// reason) for the first stage that did not pass on a failure.
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
    private readonly RtpSendSettings _settings;
    private readonly ILogger<HandlePaymentOutcome> _logger;

    public HandlePaymentOutcome(
        IPaymentCosmosDBAdapter paymentCosmosDB,
        ITabaPaySendService tabaPay,
        IServiceBusMessageService serviceBus,
        IOptions<RtpSendSettings> settings,
        ILogger<HandlePaymentOutcome> logger)
    {
        _paymentCosmosDB = paymentCosmosDB;
        _tabaPay = tabaPay;
        _serviceBus = serviceBus;
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
            // the doc should exist (ProcessPayment
            // wrote it). Abandon so a later delivery finds it — unless we've
            // tried enough times, in which case dead-letter for investigation.
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

        // TransferCompleted means LIMIT, SCREENING and LEDGER all passed in
        // Transfer. Record each as its own COMPLETED history entry (authoritative
        // — Transfer owns these stages) before calling TabaPay, so the history
        // reflects them even though TabaPay runs immediately after.
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
            // First attempt (attempt 0). Non-retryable → dead-letter now; retryable
            // → schedule a backed-off retry on the retry queue and complete. Either
            // way, no instant abandon/redelivery loop.
            await TabaPaySendFlow.HandleFailureAsync(
                _serviceBus, _logger, _settings.MaxTabaPayRetries,
                payment, ex, attempt: 0, message, messageActions, cancellationToken);
            return;
        }

        _logger.LogInformation("Payment {EvolveId} COMPLETED via TabaPay.", outcome.EvolveId);

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
            // the first stage that did not. Labels the failed stage accurately.
            payment = await WriteStageHistoryAsync(payment, outcome, isFailure: true, isNsf: isNsf);

            // Also set the doc-level terminal Status (the per-stage entry records
            // WHICH stage failed; this records the overall outcome).
            var terminalPatch = EvolvePaymentRequestHelper.GetStatusPatchOperation(
                DetermineFailedStage(outcome),
                terminalStatus,
                additionalInfo: new
                {
                    Message = $"Pipeline failure: {outcome.State}",
                    Reason = outcome.FailureReason
                });

            patched = await _paymentCosmosDB.PatchItemAsync(payment, terminalPatch) ?? payment;
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
    /// Determines which stage failed from the progress flags — the first stage
    /// that did not pass. Used for the doc-level terminal status entry.
    /// AccountResolutionFailed (no stage flags set) falls back to ACCOUNTLOOKUP.
    /// </summary>
    private static RequestStage DetermineFailedStage(PaymentMessage outcome)
    {
        if (!outcome.LimitPassed) return RequestStage.LIMIT;
        if (!outcome.ScreeningPassed) return RequestStage.SCREENING;
        if (!outcome.LedgerPosted) return RequestStage.LEDGER;
        // All flags true but still a failure (e.g. AccountResolutionFailed, or a
        // failure after the ledger) — attribute to ACCOUNTLOOKUP as a fallback.
        return RequestStage.ACCOUNTLOOKUP;
    }

    /// <summary>
    /// Loads the RTPSend payment document by evolveId. The doc's id != evolveId
    /// (the ctor generates them independently) and the container is partitioned
    /// by /evolveId, so this is a query (FindAllItemsAsync), not a point read.
    /// </summary>
    private async Task<EvolvePaymentRequest?> LookupPaymentAsync(string evolveId)
        => (await _paymentCosmosDB.FindAllItemsAsync(evolveId)).FirstOrDefault();

    /// <summary>
    /// Doc not found. Abandon to force redelivery so a later
    /// attempt finds it. Only after MaxLookupDeliveryAttempts do we dead-letter
    /// so we never silently drop the message —
    /// important because the ledger has already been debited at this point.
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
