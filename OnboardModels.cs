namespace PaymentServices.AccountResolution.Models;

// ---------------------------------------------------------------------------
// Customer Onboarding
// ---------------------------------------------------------------------------

/// <summary>
/// Request body for POST /onboard/customer
/// </summary>
public sealed class OnboardCustomerRequest
{
    public required CustomerNameRequest Name { get; set; }
    public string? TaxId { get; set; }
    public required string FintechId { get; set; }
    public string? Email { get; set; }
    public string? PhoneNumber { get; set; }
    public OnboardAddressRequest? Address { get; set; }
}

public sealed class CustomerNameRequest
{
    public string? First { get; set; }
    public string? Last { get; set; }
    public string? Company { get; set; }

    public bool IsBusiness => !string.IsNullOrWhiteSpace(Company);
}

public sealed class OnboardAddressRequest
{
    public string? Line1 { get; set; }
    public string? City { get; set; }
    public string? State { get; set; }
    public string? PostalCode { get; set; }
    public string? Country { get; set; }
}

/// <summary>
/// Response for POST /onboard/customer
/// </summary>
public sealed class OnboardCustomerResponse
{
    public required string CustomerId { get; init; }
    public required string FintechId { get; init; }
    public required string Status { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
}

// ---------------------------------------------------------------------------
// Account Onboarding
// ---------------------------------------------------------------------------

/// <summary>
/// Request body for POST /onboard/account
/// </summary>
public sealed class OnboardAccountRequest
{
    /// <summary>CustomerId returned from POST /onboard/customer</summary>
    public required string CustomerId { get; set; }

    public required string AccountNumber { get; set; }
    public required string RoutingNumber { get; set; }
    public required string FintechId { get; set; }

    /// <summary>Standard | TCHReceive | RTPPrefund etc.</summary>
    public string AccountKind { get; set; } = "Standard";

    /// <summary>Financial institution name — used for RemoteAccount.</summary>
    public string? FiName { get; set; }

    /// <summary>Financial institution address — used for RemoteAccount.</summary>
    public OnboardAddressRequest? FiAddress { get; set; }

    public string? Nickname { get; set; }
}

/// <summary>
/// Response for POST /onboard/account
/// </summary>
public sealed class OnboardAccountResponse
{
    public required string AccountId { get; init; }
    public required string RemoteAccountId { get; init; }
    public required string LedgerId { get; init; }
    public required string CustomerId { get; init; }
    public required string AccountNumber { get; init; }
    public required string Status { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
}

/// <summary>
/// Problem response for onboarding errors.
/// </summary>
public sealed class OnboardProblemResponse
{
    public required string Title { get; init; }
    public required int Status { get; init; }
    public required string Detail { get; init; }
}
