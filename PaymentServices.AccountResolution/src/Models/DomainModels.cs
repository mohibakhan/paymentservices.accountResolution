using System.Text.Json.Serialization;

namespace PaymentServices.AccountResolution.Models;

// ---------------------------------------------------------------------------
// These models mirror the existing TptchService domain entities
// stored in the tptch Cosmos DB database.
// Read-only in the AccountResolution flow — never written to during resolution.
// ---------------------------------------------------------------------------

public abstract class CosmosEntity
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = Guid.NewGuid().ToString();

    [JsonPropertyName("createdAt")]
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    [JsonPropertyName("updatedAt")]
    public DateTime UpdatedAt { get; init; } = DateTime.UtcNow;
}

/// <summary>
/// Maps to the `accounts` container.
/// Partition key: /accountNumber
/// </summary>
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

/// <summary>
/// Maps to the `remoteAccounts` container.
/// Partition key: /accountNumber
/// </summary>
public class TptchRemoteAccount : CosmosEntity
{
    [JsonPropertyName("accountNumber")]
    public string AccountNumber { get; set; } = string.Empty;

    [JsonPropertyName("fiAbaNumber")]
    public string FiAbaNumber { get; set; } = string.Empty;

    [JsonPropertyName("fiName")]
    public string FiName { get; set; } = string.Empty;

    [JsonPropertyName("ledgerId")]
    public string? LedgerId { get; set; }

    [JsonPropertyName("ownerIds")]
    public List<string> OwnerIds { get; set; } = [];

    [JsonPropertyName("nickname")]
    public string? Nickname { get; set; }
}

/// <summary>
/// Maps to the `customers` container.
/// Partition key: /id
/// </summary>
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

/// <summary>
/// Maps to the `platforms` container.
/// Partition key: /id
/// </summary>
public class TptchPlatform : CosmosEntity
{
    [JsonPropertyName("fintechId")]
    public string? FintechId { get; set; }

    [JsonPropertyName("customerIds")]
    public List<string> CustomerIds { get; set; } = [];
}

// ---------------------------------------------------------------------------
// Resolution result — returned by AccountResolutionService
// ---------------------------------------------------------------------------

/// <summary>
/// Result of resolving a single account party (source or destination).
/// Contains all IDs needed by downstream pipeline functions.
/// </summary>
public sealed class AccountResolutionResult
{
    public required string AccountId { get; init; }
    public required string LedgerId { get; init; }
    public required string RemoteAccountId { get; init; }
    public required string EntityId { get; init; }
    public string? AlloyEntityToken { get; init; }
}
