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
    /// Notifies Alloy of a new bank account via bank_account_created event.
    /// Called after a new account is successfully onboarded in Cosmos.
    /// Fire and forget — failures are logged but do not fail the onboarding.
    /// </summary>
    Task NotifyBankAccountCreatedAsync(
        string externalEntityId,
        string externalAccountId,
        string accountNumber,
        string routingNumber,
        CancellationToken cancellationToken = default);
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
            // Fire and forget — account already created in Cosmos, don't fail onboarding
            _logger.LogWarning(ex,
                "Alloy bank_account_created exception — continuing. EntityId={EntityId}",
                externalEntityId);
        }
    }
}
