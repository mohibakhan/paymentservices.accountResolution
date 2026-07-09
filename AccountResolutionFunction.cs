using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaymentServices.AccountResolution.Repositories;
using PaymentServices.AccountResolution.Services;
using PaymentServices.AccountResolution.Models;
using PaymentServices.Shared.Enums;
using PaymentServices.Shared.Infrastructure;
using PaymentServices.Shared.Interfaces;
using PaymentServices.Shared.Messages;

namespace PaymentServices.AccountResolution.Functions;

/// <summary>
/// Service Bus Trigger — picks up messages with state AccountResolutionPending.
/// Resolves source and destination accounts in parallel.
/// On success → publishes AccountResolutionCompleted (routes to Transfer).
/// On failure → publishes AccountResolutionFailed → RTPSend outcome handler.
/// </summary>
public sealed class AccountResolutionFunction
{
    private readonly IAccountResolutionService _resolutionService;
    private readonly ITransactionStateRepository _transactionStateRepository;
    private readonly IServiceBusPublisher _publisher;
    private readonly AccountResolutionSettings _settings;
    private readonly ILogger<AccountResolutionFunction> _logger;

    public AccountResolutionFunction(
        IAccountResolutionService resolutionService,
        ITransactionStateRepository transactionStateRepository,
        IServiceBusPublisher publisher,
        IOptions<AccountResolutionSettings> settings,
        ILogger<AccountResolutionFunction> logger)
    {
        _resolutionService = resolutionService;
        _transactionStateRepository = transactionStateRepository;
        _publisher = publisher;
        _settings = settings.Value;
        _logger = logger;
    }

    [Function(nameof(AccountResolutionFunction))]
    public async Task RunAsync(
        [ServiceBusTrigger(
            topicName: "payment-processing",
            subscriptionName: "account-resolution",
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
                "AccountResolution started. EvolveId={EvolveId} CorrelationId={CorrelationId}",
                message.EvolveId, message.CorrelationId);

            // Resolve source and destination accounts in parallel
            var sourceTask = _resolutionService.ResolveAsync(
                message.Source.AccountNumber, cancellationToken);

            Task<AccountResolutionResult?>? destinationTask = null;
            if (_settings.DESTINATION_ACCOUNT_LOOKUP_ENABLED)
            {
                destinationTask = _resolutionService.ResolveAsync(
                    message.Destination.AccountNumber, cancellationToken);
            }
            else
            {
                _logger.LogInformation(
                    "Destination account lookup skipped by configuration. EvolveId={EvolveId}",
                    message.EvolveId);
            }

            await Task.WhenAll(sourceTask, destinationTask ?? Task.CompletedTask);

            var sourceResult = await sourceTask;
            var destinationResult = destinationTask is not null
                ? await destinationTask
                : null;

            // Fail fast if source lookup fails, or destination lookup fails when enabled
            if (sourceResult is null || (_settings.DESTINATION_ACCOUNT_LOOKUP_ENABLED && destinationResult is null))
            {
                var failureReason = sourceResult is null
                    ? $"Source account not found: {message.Source.AccountNumber}"
                    : $"Destination account not found: {message.Destination.AccountNumber}";

                _logger.LogWarning(
                    "AccountResolution failed. EvolveId={EvolveId} Reason={Reason}",
                    message.EvolveId, failureReason);

                message.State = TransactionState.AccountResolutionFailed;
                message.FailureReason = failureReason;

                await _transactionStateRepository.UpdateAsync(
                    message.EvolveId,
                    TransactionState.AccountResolutionFailed,
                    tx => tx.FailureReason = failureReason,
                    cancellationToken);

                await _publisher.PublishAsync(message, cancellationToken);
                await messageActions.CompleteMessageAsync(serviceBusMessage, cancellationToken);
                return;
            }

            // Enrich message with resolved account details
            message.Source.AccountId = sourceResult.AccountId;
            message.Source.LedgerId = sourceResult.LedgerId;
            message.Source.RemoteAccountId = sourceResult.RemoteAccountId;
            message.Source.EntityId = sourceResult.EntityId;

            if (destinationResult is not null)
            {
                message.Destination.AccountId = destinationResult.AccountId;
                message.Destination.LedgerId = destinationResult.LedgerId;
                message.Destination.RemoteAccountId = destinationResult.RemoteAccountId;
                message.Destination.EntityId = destinationResult.EntityId;
            }

            // Update Cosmos transaction state
            await _transactionStateRepository.UpdateAsync(
                message.EvolveId,
                TransactionState.AccountResolutionCompleted,
                tx =>
                {
                    tx.SourceAccountId = sourceResult.AccountId;
                    tx.SourceLedgerId = sourceResult.LedgerId;
                    tx.SourceEntityId = sourceResult.EntityId;

                    if (destinationResult is not null)
                    {
                        tx.DestinationAccountId = destinationResult.AccountId;
                        tx.DestinationLedgerId = destinationResult.LedgerId;
                        tx.DestinationEntityId = destinationResult.EntityId;
                    }
                },
                cancellationToken);

            // Advance to Transfer (KYC/TMS removed from the path).
            // The 'transfer' subscription filter is set to AccountResolutionCompleted.
            message.State = TransactionState.AccountResolutionCompleted;

            await _publisher.PublishAsync(message, cancellationToken);

            _logger.LogInformation(
                "AccountResolution completed. EvolveId={EvolveId} SourceAccountId={SourceAccountId} DestinationAccountId={DestinationAccountId}",
                message.EvolveId,
                sourceResult.AccountId,
                destinationResult?.AccountId ?? "skipped");

            await messageActions.CompleteMessageAsync(serviceBusMessage, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "AccountResolution exception. EvolveId={EvolveId} CorrelationId={CorrelationId}",
                message?.EvolveId ?? "unknown", message?.CorrelationId ?? "unknown");

            // Dead letter the message for investigation
            await messageActions.DeadLetterMessageAsync(
                serviceBusMessage,
                deadLetterReason: "UnhandledException",
                deadLetterErrorDescription: ex.Message,
                cancellationToken: cancellationToken);
        }
    }
}
