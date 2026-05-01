using PaymentServices.Shared.Models;

namespace PaymentServices.AccountResolution.Models;

/// <summary>
/// AccountResolution-specific settings bound from <c>app:AppSettings</c>.
/// </summary>
public sealed class AccountResolutionSettings : AppSettings
{
    // -------------------------------------------------------------------------
    // Cosmos containers — reusing existing tptch containers
    // -------------------------------------------------------------------------
    public string COSMOS_ACCOUNTS_CONTAINER { get; set; } = "accounts";
    public string COSMOS_REMOTE_ACCOUNTS_CONTAINER { get; set; } = "remoteAccounts";
    public string COSMOS_CUSTOMERS_CONTAINER { get; set; } = "customers";
    public string COSMOS_PLATFORMS_CONTAINER { get; set; } = "platforms";
    public string COSMOS_TRANSACTIONS_CONTAINER { get; set; } = "tchSendTransactions";
    public string COSMOS_LEDGER_DATABASE { get; set; } = "ledgers";
    public string COSMOS_LEDGER_CONTAINER { get; set; } = "ledgers";

    // -------------------------------------------------------------------------
    // Service Bus
    // -------------------------------------------------------------------------
    public string SERVICE_BUS_SUBSCRIPTION { get; set; } = "account-resolution";

    // -------------------------------------------------------------------------
    // Alloy Events API
    // -------------------------------------------------------------------------
    public string ALLOY_BASE_URL { get; set; } = "https://sandbox.alloy.co";
    public bool ALLOY_SANDBOX { get; set; } = true;
    public string ALLOY_API_TOKEN { get; set; } = string.Empty;
    public string ALLOY_API_SECRET { get; set; } = string.Empty;
    public string ALLOY_INDIVIDUAL_KYC_JOURNEY_TOKEN { get; set; } = string.Empty;
    public string ALLOY_BUSINESS_KYC_JOURNEY_TOKEN { get; set; } = string.Empty;
    public string ALLOY_KYC_WORKFLOW_SECRET { get; set; } = string.Empty;

    // -------------------------------------------------------------------------
    // Redis cache
    // -------------------------------------------------------------------------

    /// <summary>Azure Cache for Redis connection string.</summary>
    public string REDIS_CONNSTRING { get; set; } = string.Empty;

    /// <summary>
    /// How long resolved account data is cached in hours.
    /// Default: 24 hours. Configurable per environment.
    /// DEV: 1, QA: 12, PROD: 24
    /// </summary>
    public int REDIS_ACCOUNT_CACHE_TTL_HOURS { get; set; } = 24;
}
