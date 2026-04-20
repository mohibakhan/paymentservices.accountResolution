using System.Text.Json.Serialization;

namespace PaymentServices.AccountResolution.Models;

public abstract class CosmosEntity
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = Guid.NewGuid().ToString();

    [JsonPropertyName("createdAt")]
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    [JsonPropertyName("updatedAt")]
    public DateTime UpdatedAt { get; init; } = DateTime.UtcNow;
}

public class TptchAccount : CosmosEntity
{
    [JsonPropertyName("kind")]
    public string Kind { get; set; } = "Standard";

    [JsonPropertyName("accountNumber")]
    public string AccountNumber { get; set; } = string.Empty;

    [JsonPropertyName("ledgerId")]
    public string? LedgerId { get; set; }

    [JsonPropertyName("ownerIds")]
    public List<string> OwnerIds { get; set; } = [];

    [JsonPropertyName("platformId")]
    public string? PlatformId { get; set; }
}

public class TptchRemoteAccount : CosmosEntity
{
    [JsonPropertyName("accountNumber")]
    public string AccountNumber { get; set; } = string.Empty;

    [JsonPropertyName("fiAbaNumber")]
    public string FiAbaNumber { get; set; } = string.Empty;

    [JsonPropertyName("fiName")]
    public string FiName { get; set; } = string.Empty;

    [JsonPropertyName("fiAddress")]
    public TptchAddress? FiAddress { get; set; }

    [JsonPropertyName("ledgerId")]
    public string? LedgerId { get; set; }

    [JsonPropertyName("ownerIds")]
    public List<string> OwnerIds { get; set; } = [];

    [JsonPropertyName("nickname")]
    public string? Nickname { get; set; }
}

public class TptchAddress
{
    [JsonPropertyName("line1")]
    public string? Line1 { get; set; }

    [JsonPropertyName("city")]
    public string? City { get; set; }

    [JsonPropertyName("state")]
    public string? State { get; set; }

    [JsonPropertyName("country")]
    public string? Country { get; set; }

    [JsonPropertyName("postalCode")]
    public string? PostalCode { get; set; }

    [JsonPropertyName("isPhysical")]
    public bool IsPhysical { get; set; } = true;
}

public class TptchCustomer : CosmosEntity
{
    [JsonPropertyName("name")]
    public CustomerName Name { get; set; } = null!;

    [JsonPropertyName("taxId")]
    public string? TaxId { get; set; }

    [JsonPropertyName("parentId")]
    public string? ParentId { get; set; }

    [JsonPropertyName("accountIds")]
    public List<string> AccountIds { get; set; } = [];

    [JsonPropertyName("remoteAccountIds")]
    public List<string> RemoteAccountIds { get; set; } = [];

    /// <summary>
    /// Alloy entity token — stored after entity creation at onboarding.
    /// Used by Compliance function for KYC/TMS checks.
    /// </summary>
    [JsonPropertyName("alloyEntityToken")]
    public string? AlloyEntityToken { get; set; }
}

public class CustomerName
{
    [JsonPropertyName("first")]
    public string? First { get; set; }

    [JsonPropertyName("last")]
    public string? Last { get; set; }

    [JsonPropertyName("company")]
    public string? Company { get; set; }
}

public class TptchPlatform : CosmosEntity
{
    [JsonPropertyName("fintechId")]
    public string? FintechId { get; set; }

    [JsonPropertyName("customerIds")]
    public List<string> CustomerIds { get; set; } = [];
}

/// <summary>
/// Maps to the `ledgers` container in the `ledgers` database.
/// Matches the existing ledger document structure.
/// Partition key: /id
/// </summary>
public class TptchLedger
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = Guid.NewGuid().ToString();

    [JsonPropertyName("AccountNumber")]
    public string AccountNumber { get; set; } = string.Empty;

    [JsonPropertyName("Currency")]
    public LedgerCurrency Currency { get; set; } = new();

    [JsonPropertyName("LastBalance")]
    public decimal LastBalance { get; set; } = 0;

    [JsonPropertyName("Metadata")]
    public LedgerMetadata Metadata { get; set; } = new();

    [JsonPropertyName("LedgerType")]
    public string LedgerType { get; set; } = "prefund-ledger-v2";

    [JsonPropertyName("CreatedAt")]
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    [JsonPropertyName("UpdatedAt")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public class LedgerCurrency
{
    [JsonPropertyName("Name")]
    public string Name { get; set; } = "USD";

    [JsonPropertyName("Symbol")]
    public string Symbol { get; set; } = "USD";

    [JsonPropertyName("BaseUnit")]
    public string BaseUnit { get; set; } = "Cent";

    [JsonPropertyName("Decimals")]
    public int Decimals { get; set; } = 2;
}

public class LedgerMetadata
{
    [JsonPropertyName("accountId")]
    public string? AccountId { get; set; }
}

/// <summary>
/// Result of resolving a single account party.
/// </summary>
public sealed class AccountResolutionResult
{
    public required string AccountId { get; init; }
    public required string LedgerId { get; init; }
    public required string RemoteAccountId { get; init; }
    public required string EntityId { get; init; }
    public string? AlloyEntityToken { get; init; }
}
