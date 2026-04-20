using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaymentServices.AccountResolution.Models;
using PaymentServices.AccountResolution.Repositories;

namespace PaymentServices.AccountResolution.Services;

public interface IAccountResolutionService
{
    /// <summary>
    /// Resolves a single account party by account number.
    /// Checks Redis cache first — falls back to Cosmos on cache miss or Redis unavailability.
    /// Returns null if the account is not found — caller should treat as failure.
    /// </summary>
    Task<AccountResolutionResult?> ResolveAsync(
        string accountNumber,
        CancellationToken cancellationToken = default);
}

public sealed class AccountResolutionService : IAccountResolutionService
{
    private readonly IAccountRepository _accountRepository;
    private readonly ICacheService _cacheService;
    private readonly AccountResolutionSettings _settings;
    private readonly ILogger<AccountResolutionService> _logger;

    /// <summary>Cache key prefix for resolved accounts.</summary>
    private const string CacheKeyPrefix = "account:resolved:";

    public AccountResolutionService(
        IAccountRepository accountRepository,
        ICacheService cacheService,
        IOptions<AccountResolutionSettings> settings,
        ILogger<AccountResolutionService> logger)
    {
        _accountRepository = accountRepository;
        _cacheService = cacheService;
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task<AccountResolutionResult?> ResolveAsync(
        string accountNumber,
        CancellationToken cancellationToken = default)
    {
        var cacheKey = $"{CacheKeyPrefix}{accountNumber}";
        var cacheTtl = TimeSpan.FromHours(_settings.REDIS_ACCOUNT_CACHE_TTL_HOURS);

        // -------------------------------------------------------------------------
        // Step 1 — check Redis cache first
        // -------------------------------------------------------------------------
        var cached = await _cacheService.GetAsync<AccountResolutionResult>(
            cacheKey, cancellationToken);

        if (cached is not null)
        {
            _logger.LogInformation(
                "Account resolved from cache. AccountNumber={AccountNumber} AccountId={AccountId}",
                accountNumber, cached.AccountId);
            return cached;
        }

        _logger.LogInformation(
            "Cache miss — resolving from Cosmos. AccountNumber={AccountNumber}", accountNumber);

        // -------------------------------------------------------------------------
        // Step 2 — resolve from Cosmos
        // -------------------------------------------------------------------------
        var result = await ResolveFromCosmosAsync(accountNumber, cancellationToken);

        if (result is null)
            return null;

        // -------------------------------------------------------------------------
        // Step 3 — cache the result for future payments
        // -------------------------------------------------------------------------
        await _cacheService.SetAsync(cacheKey, result, cacheTtl, cancellationToken);

        _logger.LogInformation(
            "Account resolved and cached. AccountNumber={AccountNumber} AccountId={AccountId} TTL={TTL}h",
            accountNumber, result.AccountId, _settings.REDIS_ACCOUNT_CACHE_TTL_HOURS);

        return result;
    }

    // -------------------------------------------------------------------------
    // Private — Cosmos resolution chain
    // -------------------------------------------------------------------------

    private async Task<AccountResolutionResult?> ResolveFromCosmosAsync(
        string accountNumber,
        CancellationToken cancellationToken)
    {
        // Find RemoteAccount by accountNumber
        var remoteAccount = await _accountRepository
            .GetRemoteAccountAsync(accountNumber, cancellationToken);

        if (remoteAccount is null)
        {
            _logger.LogWarning(
                "Resolution failed — RemoteAccount not found. AccountNumber={AccountNumber}",
                accountNumber);
            return null;
        }

        // Get customerId from RemoteAccount.OwnerIds
        var customerId = remoteAccount.OwnerIds.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(customerId))
        {
            _logger.LogWarning(
                "Resolution failed — RemoteAccount has no owners. AccountNumber={AccountNumber} RemoteAccountId={RemoteAccountId}",
                accountNumber, remoteAccount.Id);
            return null;
        }

        // Find standard Account by ownerId
        var account = await _accountRepository
            .GetAccountByOwnerAsync(customerId, cancellationToken);

        if (account is null)
        {
            _logger.LogWarning(
                "Resolution failed — Account not found for owner. AccountNumber={AccountNumber} CustomerId={CustomerId}",
                accountNumber, customerId);
            return null;
        }

        // Validate LedgerId exists
        if (string.IsNullOrWhiteSpace(account.LedgerId))
        {
            _logger.LogWarning(
                "Resolution failed — Account has no LedgerId. AccountNumber={AccountNumber} AccountId={AccountId}",
                accountNumber, account.Id);
            return null;
        }

        _logger.LogInformation(
            "Account resolved from Cosmos. AccountNumber={AccountNumber} AccountId={AccountId} LedgerId={LedgerId} EntityId={EntityId}",
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
