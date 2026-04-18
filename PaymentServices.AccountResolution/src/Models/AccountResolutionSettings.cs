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

    // -------------------------------------------------------------------------
    // Service Bus
    // -------------------------------------------------------------------------
    public string SERVICE_BUS_SUBSCRIPTION { get; set; } = "account-resolution";
}
