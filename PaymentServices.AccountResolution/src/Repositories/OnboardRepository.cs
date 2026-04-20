using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Logging;
using PaymentServices.AccountResolution.Models;

namespace PaymentServices.AccountResolution.Repositories;

public interface IOnboardRepository
{
    // -------------------------------------------------------------------------
    // Conflict checks
    // -------------------------------------------------------------------------

    Task<bool> CustomerExistsAsync(
        string customerId,
        CancellationToken cancellationToken = default);

    Task<bool> AccountExistsAsync(
        string accountNumber,
        string routingNumber,
        string fintechId,
        CancellationToken cancellationToken = default);

    // -------------------------------------------------------------------------
    // Reads
    // -------------------------------------------------------------------------

    Task<TptchPlatform?> GetPlatformByFintechIdAsync(
        string fintechId,
        CancellationToken cancellationToken = default);

    // -------------------------------------------------------------------------
    // Writes
    // -------------------------------------------------------------------------

    Task<TptchCustomer> CreateCustomerAsync(
        TptchCustomer customer,
        CancellationToken cancellationToken = default);

    Task<TptchAccount> CreateAccountAsync(
        TptchAccount account,
        CancellationToken cancellationToken = default);

    Task<TptchRemoteAccount> CreateRemoteAccountAsync(
        TptchRemoteAccount remoteAccount,
        CancellationToken cancellationToken = default);

    Task<TptchLedger> CreateLedgerAsync(
        TptchLedger ledger,
        CancellationToken cancellationToken = default);

    Task UpdateAccountLedgerIdAsync(
        string accountId,
        string accountNumber,
        string ledgerId,
        CancellationToken cancellationToken = default);

    Task UpdatePlatformCustomerAsync(
        string platformId,
        string customerId,
        CancellationToken cancellationToken = default);

    Task UpdateCustomerAccountsAsync(
        string customerId,
        string accountId,
        string remoteAccountId,
        CancellationToken cancellationToken = default);
}

public sealed class OnboardRepository : IOnboardRepository
{
    private readonly Container _customersContainer;
    private readonly Container _accountsContainer;
    private readonly Container _remoteAccountsContainer;
    private readonly Container _platformsContainer;
    private readonly Container _ledgersContainer;
    private readonly ILogger<OnboardRepository> _logger;

    public OnboardRepository(
        [FromKeyedServices("customers")] Container customersContainer,
        [FromKeyedServices("accounts")] Container accountsContainer,
        [FromKeyedServices("remoteAccounts")] Container remoteAccountsContainer,
        [FromKeyedServices("platforms")] Container platformsContainer,
        [FromKeyedServices("ledgers")] Container ledgersContainer,
        ILogger<OnboardRepository> logger)
    {
        _customersContainer = customersContainer;
        _accountsContainer = accountsContainer;
        _remoteAccountsContainer = remoteAccountsContainer;
        _platformsContainer = platformsContainer;
        _ledgersContainer = ledgersContainer;
        _logger = logger;
    }

    // -------------------------------------------------------------------------
    // Conflict checks
    // -------------------------------------------------------------------------

    public async Task<bool> CustomerExistsAsync(
        string customerId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await _customersContainer.ReadItemAsync<TptchCustomer>(
                customerId, new PartitionKey(customerId),
                cancellationToken: cancellationToken);
            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return false;
        }
    }

    public async Task<bool> AccountExistsAsync(
        string accountNumber,
        string routingNumber,
        string fintechId,
        CancellationToken cancellationToken = default)
    {
        // Check remoteAccounts — accountNumber is partition key
        var query = new QueryDefinition(
            "SELECT c.id FROM c WHERE c.accountNumber = @accountNumber AND c.fiAbaNumber = @routingNumber")
            .WithParameter("@accountNumber", accountNumber)
            .WithParameter("@routingNumber", routingNumber);

        using var iterator = _remoteAccountsContainer.GetItemQueryIterator<dynamic>(
            query,
            requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(accountNumber),
                MaxItemCount = 1
            });

        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(cancellationToken);
            if (page.Any()) return true;
        }

        return false;
    }

    // -------------------------------------------------------------------------
    // Reads
    // -------------------------------------------------------------------------

    public async Task<TptchPlatform?> GetPlatformByFintechIdAsync(
        string fintechId,
        CancellationToken cancellationToken = default)
    {
        var query = new QueryDefinition(
            "SELECT * FROM c WHERE c.fintechId = @fintechId")
            .WithParameter("@fintechId", fintechId);

        var results = new List<TptchPlatform>();
        using var iterator = _platformsContainer.GetItemQueryIterator<TptchPlatform>(query,
            requestOptions: new QueryRequestOptions { MaxItemCount = 1 });

        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(cancellationToken);
            results.AddRange(page);
        }

        return results.FirstOrDefault();
    }

    // -------------------------------------------------------------------------
    // Writes
    // -------------------------------------------------------------------------

    public async Task<TptchCustomer> CreateCustomerAsync(
        TptchCustomer customer,
        CancellationToken cancellationToken = default)
    {
        var response = await _customersContainer.CreateItemAsync(
            customer, new PartitionKey(customer.Id),
            cancellationToken: cancellationToken);

        _logger.LogInformation("Customer created. CustomerId={CustomerId}", customer.Id);
        return response.Resource;
    }

    public async Task<TptchAccount> CreateAccountAsync(
        TptchAccount account,
        CancellationToken cancellationToken = default)
    {
        var response = await _accountsContainer.CreateItemAsync(
            account, new PartitionKey(account.AccountNumber),
            cancellationToken: cancellationToken);

        _logger.LogInformation(
            "Account created. AccountId={AccountId} AccountNumber={AccountNumber}",
            account.Id, account.AccountNumber);
        return response.Resource;
    }

    public async Task<TptchRemoteAccount> CreateRemoteAccountAsync(
        TptchRemoteAccount remoteAccount,
        CancellationToken cancellationToken = default)
    {
        var response = await _remoteAccountsContainer.CreateItemAsync(
            remoteAccount, new PartitionKey(remoteAccount.AccountNumber),
            cancellationToken: cancellationToken);

        _logger.LogInformation(
            "RemoteAccount created. RemoteAccountId={RemoteAccountId} AccountNumber={AccountNumber}",
            remoteAccount.Id, remoteAccount.AccountNumber);
        return response.Resource;
    }

    public async Task<TptchLedger> CreateLedgerAsync(
        TptchLedger ledger,
        CancellationToken cancellationToken = default)
    {
        var response = await _ledgersContainer.CreateItemAsync(
            ledger, new PartitionKey(ledger.Id),
            cancellationToken: cancellationToken);

        _logger.LogInformation("Ledger created. LedgerId={LedgerId}", ledger.Id);
        return response.Resource;
    }

    public async Task UpdateAccountLedgerIdAsync(
        string accountId,
        string accountNumber,
        string ledgerId,
        CancellationToken cancellationToken = default)
    {
        // Patch just the ledgerId field
        var patchOperations = new[]
        {
            PatchOperation.Set("/ledgerId", ledgerId)
        };

        await _accountsContainer.PatchItemAsync<TptchAccount>(
            accountId,
            new PartitionKey(accountNumber),
            patchOperations,
            cancellationToken: cancellationToken);

        _logger.LogInformation(
            "Account ledgerId updated. AccountId={AccountId} LedgerId={LedgerId}",
            accountId, ledgerId);
    }

    public async Task UpdatePlatformCustomerAsync(
        string platformId,
        string customerId,
        CancellationToken cancellationToken = default)
    {
        var patchOperations = new[]
        {
            PatchOperation.Add("/customerIds/-", customerId)
        };

        await _platformsContainer.PatchItemAsync<TptchPlatform>(
            platformId,
            new PartitionKey(platformId),
            patchOperations,
            cancellationToken: cancellationToken);
    }

    public async Task UpdateCustomerAccountsAsync(
        string customerId,
        string accountId,
        string remoteAccountId,
        CancellationToken cancellationToken = default)
    {
        var patchOperations = new[]
        {
            PatchOperation.Add("/accountIds/-", accountId),
            PatchOperation.Add("/remoteAccountIds/-", remoteAccountId)
        };

        await _customersContainer.PatchItemAsync<TptchCustomer>(
            customerId,
            new PartitionKey(customerId),
            patchOperations,
            cancellationToken: cancellationToken);
    }
}
