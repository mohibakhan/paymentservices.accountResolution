using Microsoft.Extensions.Logging;
using PaymentServices.AccountResolution.Models;
using PaymentServices.AccountResolution.Repositories;

namespace PaymentServices.AccountResolution.Services;

public interface IAccountResolutionService
{
    /// <summary>
    /// Resolves a single account party by account number.
    /// Returns null if the account is not found — caller should treat as failure.
    /// </summary>
    Task<AccountResolutionResult?> ResolveAsync(
        string accountNumber,
        CancellationToken cancellationToken = default);
}

public sealed class AccountResolutionService : IAccountResolutionService
{
    private readonly IAccountRepository _accountRepository;
    private readonly ILogger<AccountResolutionService> _logger;

    public AccountResolutionService(
        IAccountRepository accountRepository,
        ILogger<AccountResolutionService> logger)
    {
        _accountRepository = accountRepository;
        _logger = logger;
    }

    public async Task<AccountResolutionResult?> ResolveAsync(
        string accountNumber,
        CancellationToken cancellationToken = default)
    {
        // Step 1 — find RemoteAccount by accountNumber
        var remoteAccount = await _accountRepository
            .GetRemoteAccountAsync(accountNumber, cancellationToken);

        if (remoteAccount is null)
        {
            _logger.LogWarning(
                "Resolution failed — RemoteAccount not found. AccountNumber={AccountNumber}",
                accountNumber);
            return null;
        }

        // Step 2 — get customerId from RemoteAccount.OwnerIds
        var customerId = remoteAccount.OwnerIds.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(customerId))
        {
            _logger.LogWarning(
                "Resolution failed — RemoteAccount has no owners. AccountNumber={AccountNumber} RemoteAccountId={RemoteAccountId}",
                accountNumber, remoteAccount.Id);
            return null;
        }

        // Step 3 — find standard Account by ownerId
        var account = await _accountRepository
            .GetAccountByOwnerAsync(customerId, cancellationToken);

        if (account is null)
        {
            _logger.LogWarning(
                "Resolution failed — Account not found for owner. AccountNumber={AccountNumber} CustomerId={CustomerId}",
                accountNumber, customerId);
            return null;
        }

        // Step 4 — validate LedgerId exists
        if (string.IsNullOrWhiteSpace(account.LedgerId))
        {
            _logger.LogWarning(
                "Resolution failed — Account has no LedgerId. AccountNumber={AccountNumber} AccountId={AccountId}",
                accountNumber, account.Id);
            return null;
        }

        _logger.LogInformation(
            "Account resolved successfully. AccountNumber={AccountNumber} AccountId={AccountId} LedgerId={LedgerId} EntityId={EntityId}",
            accountNumber, account.Id, account.LedgerId, customerId);

        return new AccountResolutionResult
        {
            AccountId = account.Id,
            LedgerId = account.LedgerId,
            RemoteAccountId = remoteAccount.Id,
            EntityId = customerId
        };
    }
}
