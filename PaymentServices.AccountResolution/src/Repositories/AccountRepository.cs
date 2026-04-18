using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Logging;
using PaymentServices.AccountResolution.Models;

namespace PaymentServices.AccountResolution.Repositories;

public interface IAccountRepository
{
    /// <summary>
    /// Finds a RemoteAccount by account number.
    /// Returns null if not found.
    /// </summary>
    Task<TptchRemoteAccount?> GetRemoteAccountAsync(
        string accountNumber,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Finds a standard Account where OwnerIds contains the given customerId
    /// and Kind is Standard.
    /// </summary>
    Task<TptchAccount?> GetAccountByOwnerAsync(
        string customerId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Finds a Customer by id.
    /// </summary>
    Task<TptchCustomer?> GetCustomerAsync(
        string customerId,
        CancellationToken cancellationToken = default);
}

public sealed class AccountRepository : IAccountRepository
{
    private readonly Container _accountsContainer;
    private readonly Container _remoteAccountsContainer;
    private readonly Container _customersContainer;
    private readonly ILogger<AccountRepository> _logger;

    public AccountRepository(
        [FromKeyedServices("accounts")] Container accountsContainer,
        [FromKeyedServices("remoteAccounts")] Container remoteAccountsContainer,
        [FromKeyedServices("customers")] Container customersContainer,
        ILogger<AccountRepository> logger)
    {
        _accountsContainer = accountsContainer;
        _remoteAccountsContainer = remoteAccountsContainer;
        _customersContainer = customersContainer;
        _logger = logger;
    }

    public async Task<TptchRemoteAccount?> GetRemoteAccountAsync(
        string accountNumber,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Looking up RemoteAccount for AccountNumber={AccountNumber}", accountNumber);

        // Partition key is accountNumber — direct point read not possible
        // since we don't have the id, so use a query scoped to the partition
        var query = new QueryDefinition(
            "SELECT * FROM c WHERE c.accountNumber = @accountNumber")
            .WithParameter("@accountNumber", accountNumber);

        var results = new List<TptchRemoteAccount>();
        using var iterator = _remoteAccountsContainer.GetItemQueryIterator<TptchRemoteAccount>(
            query,
            requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(accountNumber),
                MaxItemCount = 1
            });

        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(cancellationToken);
            results.AddRange(page);
        }

        var result = results.FirstOrDefault();
        if (result is null)
            _logger.LogWarning(
                "RemoteAccount not found for AccountNumber={AccountNumber}", accountNumber);

        return result;
    }

    public async Task<TptchAccount?> GetAccountByOwnerAsync(
        string customerId,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Looking up Account for CustomerId={CustomerId}", customerId);

        // Cross-partition query — accounts are partitioned by accountNumber
        // but we're searching by ownerId
        var query = new QueryDefinition(
            "SELECT * FROM c WHERE ARRAY_CONTAINS(c.ownerIds, @customerId) AND c.kind = 'Standard'")
            .WithParameter("@customerId", customerId);

        var results = new List<TptchAccount>();
        using var iterator = _accountsContainer.GetItemQueryIterator<TptchAccount>(
            query,
            requestOptions: new QueryRequestOptions { MaxItemCount = 1 });

        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(cancellationToken);
            results.AddRange(page);
        }

        var result = results.FirstOrDefault();
        if (result is null)
            _logger.LogWarning(
                "Account not found for CustomerId={CustomerId}", customerId);

        return result;
    }

    public async Task<TptchCustomer?> GetCustomerAsync(
        string customerId,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Looking up Customer for CustomerId={CustomerId}", customerId);

        try
        {
            var response = await _customersContainer.ReadItemAsync<TptchCustomer>(
                customerId,
                new PartitionKey(customerId),
                cancellationToken: cancellationToken);

            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            _logger.LogWarning(
                "Customer not found for CustomerId={CustomerId}", customerId);
            return null;
        }
    }
}
