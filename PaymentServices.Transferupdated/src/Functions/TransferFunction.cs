using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using PaymentServices.Shared.Enums;
using PaymentServices.Shared.Infrastructure;
using PaymentServices.Shared.Interfaces;
using PaymentServices.Shared.Messages;
using PaymentServices.Transfer.Exceptions;
using PaymentServices.Transfer.Repositories;
using PaymentServices.Transfer.Services;

namespace PaymentServices.Transfer.Functions;

/// <summary>
/// Service Bus Trigger — subscribed to the 'transfer' subscription
/// (filter: State = AccountResolutionCompleted; KYC/TMS removed).
///
/// Runs LIMIT → SCREENING → LEDGER (source debit via the Evolve NuGet).
/// On success → publishes TransferCompleted (RTPSend reacts → TabaPay).
/// On business failure (limit/screening/NSF) → publishes TransferFailed and
///   COMPLETES the message (terminal, no retry/DLQ).
/// On unexpected/transient failure → publishes TransferFailed (best effort)
///   and DEAD-LETTERS for investigation.
/// </summary>
public sealed class TransferFunction
{
    private readonly ITransferService _transferService;
    private readonly ITransactionStateRepository _transactionStateRepository;
    private readonly IServiceBusPublisher _publisher;
    private readonly ILogger<TransferFunction> _logger;

    public TransferFunction(
        ITransferService transferService,
        ITransactionStateRepository transactionStateRepository,
        IServiceBusPublisher publisher,
        ILogger<TransferFunction> logger)
    {
        _transferService = transferService;
        _transactionStateRepository = transactionStateRepository;
        _publisher = publisher;
        _logger = logger;
    }

    [Function(nameof(TransferFunction))]
    public async Task RunAsync(
        [ServiceBusTrigger(
            topicName: "payment-processing",
            subscriptionName: "transfer",
            Connection = "SERVICE_BUS_CONNSTRING")]
        ServiceBusReceivedMessage serviceBusMessage,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        PaymentMessage? message = null;

        try
        {
            message = ServiceBusPublisher.Deserialize(serviceBusMessage);

            _logger.LogInformation(
                "Transfer started. EvolveId={EvolveId} CorrelationId={CorrelationId} Amount={Amount}",
                message.EvolveId, message.CorrelationId, message.Amount);

            // Idempotency — if this transaction already reached a terminal state
            // (e.g. a prior delivery completed the ledger debit but the message
            // settle was lost and the broker redelivered), do NOT re-run the
            // ledger. Just complete the message. Prevents a double debit.
            var currentState = await _transactionStateRepository.GetStateAsync(
                message.EvolveId, cancellationToken);

            if (currentState is TransactionState.TransferCompleted
                              or TransactionState.TransferFailed)
            {
                _logger.LogInformation(
                    "Transfer already terminal ({State}) for EvolveId={EvolveId}; skipping re-processing.",
                    currentState, message.EvolveId);
                await SafeCompleteAsync(messageActions, serviceBusMessage, message.EvolveId, cancellationToken);
                return;
            }

            // Mark in-progress
            await _transactionStateRepository.UpdateStateAsync(
                message.EvolveId,
                TransactionState.TransferPending,
                cancellationToken: cancellationToken);

            // LIMIT → SCREENING → LEDGER (source debit)
            var result = await _transferService.ExecuteAsync(message, cancellationToken);

            // Success — enrich + advance to TransferCompleted
            message.EveTransactionId = result.EveTransactionId;
            message.GluIdSource = result.GluIdSource;
            message.GluIdDestination = result.GluIdDestination;
            message.State = TransactionState.TransferCompleted;

            await _transactionStateRepository.UpdateStateAsync(
                message.EvolveId,
                TransactionState.TransferCompleted,
                tx =>
                {
                    tx.EveTransactionId = result.EveTransactionId;
                    tx.GluIdSource = result.GluIdSource;
                    tx.GluIdDestination = result.GluIdDestination;
                },
                cancellationToken);

            // Publish — RTPSend's outcome subscription reacts to this.
            await _publisher.PublishAsync(message, cancellationToken);

            _logger.LogInformation(
                "Transfer completed. EvolveId={EvolveId} GluIdSource={GluIdSource}",
                message.EvolveId, result.GluIdSource);

            await SafeCompleteAsync(messageActions, serviceBusMessage, message?.EvolveId, cancellationToken);
        }
        catch (Exception ex) when (
            ex is InsufficientFundsException
               or LimitExceededException
               or ScreeningRejectedException)
        {
            // TERMINAL business failure — publish TransferFailed and complete the
            // message. Retrying won't change the outcome, so this must NEVER DLQ.
            // All side effects are best-effort and individually guarded so that a
            // failure in one (e.g. a lost message lock on complete) cannot cascade
            // the message into the dead-letter queue.
            _logger.LogWarning(ex,
                "Transfer terminally failed. EvolveId={EvolveId} Reason={Reason}",
                message?.EvolveId ?? "unknown", ex.Message);

            if (message is not null)
            {
                message.State = TransactionState.TransferFailed;
                message.FailureReason = ex.Message;

                try
                {
                    await _transactionStateRepository.UpdateStateAsync(
                        message.EvolveId,
                        TransactionState.TransferFailed,
                        tx => tx.FailureReason = ex.Message,
                        cancellationToken);
                }
                catch (Exception patchEx)
                {
                    _logger.LogError(patchEx,
                        "Failed to patch TransferFailed state. EvolveId={EvolveId}", message.EvolveId);
                }

                try
                {
                    await _publisher.PublishAsync(message, cancellationToken);
                }
                catch (Exception pubEx)
                {
                    _logger.LogError(pubEx,
                        "Failed to publish terminal TransferFailed. EvolveId={EvolveId}", message.EvolveId);
                }
            }

            // Settle as terminal. Guarded so a lock-lost / settle error does not
            // escape and trigger redelivery → DLQ.
            await SafeCompleteAsync(messageActions, serviceBusMessage, message?.EvolveId, cancellationToken);
        }
        catch (Exception ex)
        {
            // UNEXPECTED / transient — publish TransferFailed (best effort) then
            // dead-letter for investigation.
            _logger.LogError(ex,
                "Transfer exception. EvolveId={EvolveId} CorrelationId={CorrelationId}",
                message?.EvolveId ?? "unknown", message?.CorrelationId ?? "unknown");

            if (message is not null)
            {
                try
                {
                    message.State = TransactionState.TransferFailed;
                    message.FailureReason = ex.Message;

                    await _transactionStateRepository.UpdateStateAsync(
                        message.EvolveId,
                        TransactionState.TransferFailed,
                        tx => tx.FailureReason = ex.Message,
                        cancellationToken);

                    await _publisher.PublishAsync(message, cancellationToken);
                }
                catch (Exception innerEx)
                {
                    _logger.LogError(innerEx,
                        "Failed to publish TransferFailed. EvolveId={EvolveId}", message.EvolveId);
                }
            }

            await SafeDeadLetterAsync(
                messageActions, serviceBusMessage, "UnhandledException", ex.Message,
                message?.EvolveId, cancellationToken);
        }
    }

    /// <summary>
    /// Completes the message, swallowing settle errors (e.g. MessageLockLost).
    /// A failed settle on an already-handled message must not bubble up and
    /// cause redelivery; the work is done, so we log and move on.
    /// </summary>
    private async Task SafeCompleteAsync(
        ServiceBusMessageActions actions,
        ServiceBusReceivedMessage sbMessage,
        string? evolveId,
        CancellationToken cancellationToken)
    {
        try
        {
            await actions.CompleteMessageAsync(sbMessage, cancellationToken);
        }
        catch (Exception ex)
        {
            // If the lock was lost the broker will redeliver; idempotency on the
            // next delivery (terminal-state check) keeps that safe. Do not rethrow.
            _logger.LogWarning(ex,
                "CompleteMessage failed (likely lock lost). EvolveId={EvolveId}", evolveId ?? "unknown");
        }
    }

    private async Task SafeDeadLetterAsync(
        ServiceBusMessageActions actions,
        ServiceBusReceivedMessage sbMessage,
        string reason,
        string description,
        string? evolveId,
        CancellationToken cancellationToken)
    {
        try
        {
            await actions.DeadLetterMessageAsync(
                sbMessage,
                deadLetterReason: reason,
                deadLetterErrorDescription: description,
                cancellationToken: cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex,
                "DeadLetter failed (likely lock lost). EvolveId={EvolveId}", evolveId ?? "unknown");
        }
    }
}