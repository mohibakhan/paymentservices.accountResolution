using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Logging;
using PaymentServices.Shared.Enums;
using PaymentServices.Shared.Models;

namespace PaymentServices.AccountResolution.Repositories;

public interface ITransactionStateRepository
{
    Task UpdateAsync(
        string evolveId,
        TransactionState state,
        Action<CosmosTransaction> update,
        CancellationToken cancellationToken = default);
}

public sealed class TransactionStateRepository : ITransactionStateRepository
{
    private readonly Container _container;
    private readonly ILogger<TransactionStateRepository> _logger;

    public TransactionStateRepository(
        [FromKeyedServices("transactions")] Container container,
        ILogger<TransactionStateRepository> logger)
    {
        _container = container;
        _logger = logger;
    }

    public async Task UpdateAsync(
        string evolveId,
        TransactionState state,
        Action<CosmosTransaction> update,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var response = await _container.ReadItemAsync<CosmosTransaction>(
                evolveId,
                new PartitionKey(evolveId),
                cancellationToken: cancellationToken);

            var transaction = response.Resource;
            transaction.State = state;
            transaction.LastUpdatedAt = DateTimeOffset.UtcNow;

            // Apply any additional updates (e.g. set accountIds, ledgerIds)
            update(transaction);

            await _container.ReplaceItemAsync(
                transaction,
                evolveId,
                new PartitionKey(evolveId),
                cancellationToken: cancellationToken);

            _logger.LogInformation(
                "Transaction state updated. EvolveId={EvolveId} State={State}",
                evolveId, state);
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            _logger.LogError(
                "Transaction not found for state update. EvolveId={EvolveId}", evolveId);
            throw;
        }
    }
}
