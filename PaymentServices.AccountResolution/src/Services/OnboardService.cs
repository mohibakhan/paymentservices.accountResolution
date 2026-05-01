using Microsoft.Extensions.Logging;
using PaymentServices.AccountResolution.Models;
using PaymentServices.AccountResolution.Repositories;

namespace PaymentServices.AccountResolution.Services;

public interface IOnboardService
{
    Task<OnboardCustomerResponse> OnboardCustomerAsync(
        OnboardCustomerRequest request,
        CancellationToken cancellationToken = default);

    Task<OnboardAccountResponse> OnboardAccountAsync(
        OnboardAccountRequest request,
        CancellationToken cancellationToken = default);
}

public sealed class OnboardService : IOnboardService
{
    private readonly IOnboardRepository _repository;
    private readonly IAlloyEventsService _alloyEventsService;
    private readonly ILogger<OnboardService> _logger;

    public OnboardService(
        IOnboardRepository repository,
        IAlloyEventsService alloyEventsService,
        ILogger<OnboardService> logger)
    {
        _repository = repository;
        _alloyEventsService = alloyEventsService;
        _logger = logger;
    }

    // -------------------------------------------------------------------------
    // Customer Onboarding
    // -------------------------------------------------------------------------

    public async Task<OnboardCustomerResponse> OnboardCustomerAsync(
        OnboardCustomerRequest request,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Onboarding customer. FintechId={FintechId}", request.FintechId);

        // Resolve platform by fintechId
        var platform = await _repository.GetPlatformByFintechIdAsync(
            request.FintechId, cancellationToken);

        if (platform is null)
            throw new InvalidOperationException(
                $"Platform not found for FintechId: {request.FintechId}");

        // Build customer document
        var customer = new TptchCustomer
        {
            Name = new CustomerName
            {
                First = request.Name.First,
                Last = request.Name.Last,
                Company = request.Name.Company
            },
            TaxId = request.TaxId?.Replace("-", ""),
            ParentId = platform.Id,
            AccountIds = [],
            RemoteAccountIds = []
        };

        // Persist customer
        var created = await _repository.CreateCustomerAsync(customer, cancellationToken);

        // Link customer to platform
        await _repository.UpdatePlatformCustomerAsync(
            platform.Id, created.Id, cancellationToken);

        _logger.LogInformation(
            "Customer onboarded. CustomerId={CustomerId} FintechId={FintechId}",
            created.Id, request.FintechId);

        // Run KYC via Alloy — registers entity so bank_account_created works next
        var kycResult = await _alloyEventsService.RunKycAsync(
            customerId: created.Id,
            nameFirst: request.Name.First,
            nameLast: request.Name.Last,
            businessName: request.Name.Company,
            isBusiness: request.Name.IsBusiness,
            address: request.Address,
            cancellationToken: cancellationToken);

        _logger.LogInformation(
            "KYC complete. CustomerId={CustomerId} Outcome={Outcome}",
            created.Id, kycResult.Outcome);

        return new OnboardCustomerResponse
        {
            CustomerId = created.Id,
            FintechId = request.FintechId,
            Status = "Created",
            KycOutcome = kycResult.Outcome
        };
    }

    // -------------------------------------------------------------------------
    // Account Onboarding
    // -------------------------------------------------------------------------

    public async Task<OnboardAccountResponse> OnboardAccountAsync(
        OnboardAccountRequest request,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Onboarding account. CustomerId={CustomerId} AccountNumber={AccountNumber}",
            request.CustomerId, request.AccountNumber);

        // Conflict check — accountNumber + routingNumber + fintechId
        var exists = await _repository.AccountExistsAsync(
            request.AccountNumber, request.RoutingNumber, request.FintechId,
            cancellationToken);

        if (exists)
            throw new ConflictException(
                $"Account already exists for AccountNumber={request.AccountNumber} " +
                $"RoutingNumber={request.RoutingNumber} FintechId={request.FintechId}");

        // Verify customer exists
        var customerExists = await _repository.CustomerExistsAsync(
            request.CustomerId, cancellationToken);

        if (!customerExists)
            throw new InvalidOperationException(
                $"Customer not found: {request.CustomerId}. " +
                "Call POST /onboard/customer first.");

        // Step 1 — Create RemoteAccount
        var remoteAccount = new TptchRemoteAccount
        {
            AccountNumber = request.AccountNumber,
            FiAbaNumber = request.RoutingNumber,
            FiName = request.FiName ?? "Unknown",
            FiAddress = request.FiAddress is null ? null : new TptchAddress
            {
                Line1 = request.FiAddress.Line1,
                City = request.FiAddress.City,
                State = request.FiAddress.State,
                Country = request.FiAddress.Country ?? "US",
                PostalCode = request.FiAddress.PostalCode,
                IsPhysical = true
            },
            Nickname = request.Nickname ?? "remote account",
            OwnerIds = [request.CustomerId]
        };

        var createdRemoteAccount = await _repository
            .CreateRemoteAccountAsync(remoteAccount, cancellationToken);

        // Step 2 — Create Account (without ledgerId first)
        var account = new TptchAccount
        {
            Kind = request.AccountKind,
            AccountNumber = request.AccountNumber,
            OwnerIds = [request.CustomerId]
        };

        var createdAccount = await _repository
            .CreateAccountAsync(account, cancellationToken);

        // Step 3 — Create Ledger
        var ledger = new TptchLedger
        {
            AccountNumber = request.AccountNumber,
            LastBalance = 0,
            LedgerType = "prefund-ledger-v2",
            Metadata = new LedgerMetadata
            {
                AccountId = request.AccountNumber
            },
            Currency = new LedgerCurrency
            {
                Name = "USD",
                Symbol = "USD",
                BaseUnit = "Cent",
                Decimals = 2
            }
        };

        var createdLedger = await _repository
            .CreateLedgerAsync(ledger, cancellationToken);

        // Step 4 — Patch Account with ledgerId
        await _repository.UpdateAccountLedgerIdAsync(
            createdAccount.Id,
            createdAccount.AccountNumber,
            createdLedger.Id,
            cancellationToken);

        // Step 5 — Link account and remoteAccount back to customer
        await _repository.UpdateCustomerAccountsAsync(
            request.CustomerId,
            createdAccount.Id,
            createdRemoteAccount.Id,
            cancellationToken);

        _logger.LogInformation(
            "Account onboarded. AccountId={AccountId} RemoteAccountId={RemoteAccountId} LedgerId={LedgerId}",
            createdAccount.Id, createdRemoteAccount.Id, createdLedger.Id);

        // Step 6 — Notify Alloy of new bank account (fire and forget)
        await _alloyEventsService.NotifyBankAccountCreatedAsync(
            externalEntityId: request.CustomerId,
            externalAccountId: createdAccount.Id,
            accountNumber: request.AccountNumber,
            routingNumber: request.RoutingNumber,
            cancellationToken: cancellationToken);

        return new OnboardAccountResponse
        {
            AccountId = createdAccount.Id,
            RemoteAccountId = createdRemoteAccount.Id,
            LedgerId = createdLedger.Id,
            CustomerId = request.CustomerId,
            AccountNumber = request.AccountNumber,
            Status = "Created"
        };
    }
}

/// <summary>
/// Thrown when an account already exists — maps to HTTP 409 Conflict.
/// </summary>
public sealed class ConflictException : Exception
{
    public ConflictException(string message) : base(message) { }
}
