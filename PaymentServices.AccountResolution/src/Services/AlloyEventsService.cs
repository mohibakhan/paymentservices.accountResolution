using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaymentServices.AccountResolution.Models;

namespace PaymentServices.AccountResolution.Services;

public interface IAlloyEventsService
{
    /// <summary>
    /// Runs KYC for a customer via Alloy Journey Applications API.
    /// POST /v1/journeys/{journeyToken}/applications
    /// Called during customer onboarding to register entity in Alloy.
    /// Returns the outcome: "Approved" | "Manual Review" | "Denied"
    /// </summary>
    Task<AlloyKycResult> RunKycAsync(
        string customerId,
        string? nameFirst,
        string? nameLast,
        string? businessName,
        bool isBusiness,
        OnboardAddressRequest? address,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Notifies Alloy of a new bank account via bank_account_created event.
    /// POST /v1/events (event_type: "bank_account_created")
    /// Called after account creation in Cosmos.
    /// Fire and forget — failures are logged but do not fail onboarding.
    /// </summary>
    Task NotifyBankAccountCreatedAsync(
        string externalEntityId,
        string externalAccountId,
        string accountNumber,
        string routingNumber,
        CancellationToken cancellationToken = default);
}

public sealed class AlloyKycResult
{
    public string Outcome { get; init; } = "Approved";
    public List<string> Tags { get; init; } = [];
    public bool Success { get; init; } = true;
    public string? ErrorMessage { get; init; }
}

public sealed class AlloyEventsService : IAlloyEventsService
{
    private readonly HttpClient _httpClient;
    private readonly AccountResolutionSettings _settings;
    private readonly ILogger<AlloyEventsService> _logger;

    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public AlloyEventsService(
        HttpClient httpClient,
        IOptions<AccountResolutionSettings> settings,
        ILogger<AlloyEventsService> logger)
    {
        _httpClient = httpClient;
        _settings = settings.Value;
        _logger = logger;
    }

    // -------------------------------------------------------------------------
    // KYC — POST /v1/journeys/{journeyToken}/applications
    // -------------------------------------------------------------------------

    public async Task<AlloyKycResult> RunKycAsync(
        string customerId,
        string? nameFirst,
        string? nameLast,
        string? businessName,
        bool isBusiness,
        OnboardAddressRequest? address,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_settings.ALLOY_BASE_URL) ||
            string.IsNullOrWhiteSpace(_settings.ALLOY_INDIVIDUAL_KYC_JOURNEY_TOKEN))
        {
            _logger.LogWarning(
                "Alloy KYC not configured — skipping. CustomerId={CustomerId}", customerId);
            return new AlloyKycResult { Outcome = "Approved", Success = true };
        }

        try
        {
            var journeyToken = isBusiness
                ? _settings.ALLOY_BUSINESS_KYC_JOURNEY_TOKEN
                : _settings.ALLOY_INDIVIDUAL_KYC_JOURNEY_TOKEN;

            var url = $"{_settings.ALLOY_BASE_URL}/v1/journeys/{journeyToken}/applications?fullData=true";

            var entity = new
            {
                branch_name = isBusiness ? "businesses" : "persons",
                name_first = isBusiness ? null : nameFirst,
                name_last = isBusiness ? null : nameLast,
                business_name = isBusiness ? businessName : null,
                addresses = address is null ? null : new[]
                {
                    new
                    {
                        type = "primary",
                        line_1 = address.Line1,
                        city = address.City,
                        state = address.State,
                        postal_code = address.PostalCode,
                        country_code = address.Country ?? "US"
                    }
                },
                identifiers = new { external_entity_id = customerId },
                meta = new { }
            };

            var requestBody = new { entities = new[] { entity } };
            var json = JsonSerializer.Serialize(requestBody, _jsonOptions);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            var credentials = Convert.ToBase64String(
                Encoding.UTF8.GetBytes(
                    $"{journeyToken}:{_settings.ALLOY_KYC_WORKFLOW_SECRET}"));

            var request = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = content
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Basic", credentials);

            if (_settings.ALLOY_SANDBOX)
                request.Headers.Add("alloy-sandbox", "true");

            var response = await _httpClient.SendAsync(request, cancellationToken);
            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "Alloy KYC failed. CustomerId={CustomerId} StatusCode={StatusCode} Body={Body}",
                    customerId, (int)response.StatusCode, responseBody);

                return new AlloyKycResult
                {
                    Outcome = "Denied",
                    Success = false,
                    ErrorMessage = $"Alloy KYC returned {(int)response.StatusCode}"
                };
            }

            // Parse complete_outcome from response
            using var doc = JsonDocument.Parse(responseBody);
            var root = doc.RootElement;

            var outcome = "Approved";
            if (root.TryGetProperty("complete_outcome", out var outcomeEl) &&
                outcomeEl.ValueKind != JsonValueKind.Null)
                outcome = outcomeEl.GetString() ?? "Approved";
            else if (root.TryGetProperty("journey_application_status", out var statusEl))
                outcome = statusEl.GetString() ?? "Approved";

            // Parse tags from _embedded.entity_applications[0].output.tags
            var tags = new List<string>();
            if (root.TryGetProperty("_embedded", out var embedded) &&
                embedded.TryGetProperty("entity_applications", out var apps) &&
                apps.GetArrayLength() > 0)
            {
                var firstApp = apps[0];
                if (firstApp.TryGetProperty("output", out var output) &&
                    output.TryGetProperty("tags", out var tagsEl))
                {
                    foreach (var tag in tagsEl.EnumerateArray())
                        tags.Add(tag.GetString() ?? string.Empty);
                }
            }

            _logger.LogInformation(
                "Alloy KYC complete. CustomerId={CustomerId} Outcome={Outcome} Tags={Tags}",
                customerId, outcome, string.Join(", ", tags));

            return new AlloyKycResult
            {
                Outcome = outcome,
                Tags = tags,
                Success = true
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex,
                "Alloy KYC exception — continuing. CustomerId={CustomerId}", customerId);

            return new AlloyKycResult
            {
                Outcome = "Approved",
                Success = false,
                ErrorMessage = ex.Message
            };
        }
    }

    // -------------------------------------------------------------------------
    // Bank Account Created — POST /v1/events
    // -------------------------------------------------------------------------

    public async Task NotifyBankAccountCreatedAsync(
        string externalEntityId,
        string externalAccountId,
        string accountNumber,
        string routingNumber,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_settings.ALLOY_BASE_URL) ||
            string.IsNullOrWhiteSpace(_settings.ALLOY_API_TOKEN))
        {
            _logger.LogWarning(
                "Alloy not configured — skipping bank_account_created. EntityId={EntityId}",
                externalEntityId);
            return;
        }

        try
        {
            var url = $"{_settings.ALLOY_BASE_URL}/v1/events";

            var requestBody = new
            {
                event_type = "bank_account_created",
                data = new
                {
                    external_entity_id = externalEntityId,
                    external_account_id = externalAccountId,
                    timestamp = DateTime.UtcNow.ToString("o"),
                    account_class = "deposit",
                    account_name = "Evolve Account",
                    account_number = accountNumber,
                    routing_number = routingNumber,
                    currency = "USD",
                    status = "Active",
                    account_balance = 0,
                    entities = new[]
                    {
                        new
                        {
                            account_holder_type = "primary",
                            external_entity_id = externalEntityId
                        }
                    },
                    meta = new { },
                    supplemental_data = new { processor_token = "" }
                }
            };

            var json = JsonSerializer.Serialize(requestBody, _jsonOptions);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            var credentials = Convert.ToBase64String(
                Encoding.UTF8.GetBytes(
                    $"{_settings.ALLOY_API_TOKEN}:{_settings.ALLOY_API_SECRET}"));

            var request = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = content
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Basic", credentials);

            var response = await _httpClient.SendAsync(request, cancellationToken);
            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "Alloy bank_account_created failed. EntityId={EntityId} StatusCode={StatusCode} Body={Body}",
                    externalEntityId, (int)response.StatusCode, responseBody);
                return;
            }

            _logger.LogInformation(
                "Alloy bank_account_created accepted. EntityId={EntityId} AccountId={AccountId}",
                externalEntityId, externalAccountId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex,
                "Alloy bank_account_created exception — continuing. EntityId={EntityId}",
                externalEntityId);
        }
    }
}
