"rtpSend:AppSettings:TRANSFER_TPTCH_STATUS_URL": "https://fa-pmtsvc-transfer-dev-centralus.azurewebsites.net/api/tptch/status?code=<transfer-function-key>"

public string? TRANSFER_TPTCH_STATUS_URL { get; set; }


using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaymentServices.RTPSend.Settings;

namespace PaymentServices.RTPSend.Services;

public interface ITransferStatusClient
{
    /// <summary>
    /// Reports the final TabaPay outcome to Transfer's tptch/status endpoint.
    /// "COMPLETED" on TabaPay success; "FAILED" only on a TERMINAL (non-retryable)
    /// TabaPay failure — retryable failures are NOT reported, since the payment is
    /// still being retried and hasn't finally failed.
    /// </summary>
    Task ReportStatusAsync(string evolveId, string status, CancellationToken cancellationToken = default);
}

/// <summary>
/// Typed HttpClient for Transfer's POST /api/tptch/status. Mirrors GatewayClient:
/// config-driven URL (the Azure Functions key is embedded as the ?code= query
/// parameter, as in GATEWAY_TPTCH_SEND_URL).
///
/// NOTE — unlike GatewayClient, this client is BEST-EFFORT and never throws.
/// It is called AFTER the payment has already settled (TabaPay has run and the
/// Service Bus message is about to be completed), so a failed status callback
/// must not fail the function, trigger a redelivery, or re-process the payment.
/// Failures are logged for follow-up instead.
/// </summary>
public sealed class TransferStatusClient : ITransferStatusClient
{
    public const string CompletedStatus = "COMPLETED";
    public const string FailedStatus = "FAILED";

    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    private readonly HttpClient _httpClient;
    private readonly RtpSendSettings _settings;
    private readonly ILogger<TransferStatusClient> _logger;

    public TransferStatusClient(
        HttpClient httpClient,
        IOptions<RtpSendSettings> settings,
        ILogger<TransferStatusClient> logger)
    {
        _httpClient = httpClient;
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task ReportStatusAsync(
        string evolveId, string status, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_settings.TRANSFER_TPTCH_STATUS_URL))
        {
            _logger.LogWarning(
                "TRANSFER_TPTCH_STATUS_URL is not configured; skipping status callback. " +
                "EvolveId={EvolveId} Status={Status}", evolveId, status);
            return;
        }

        var body = new TptchStatusRequest
        {
            EvolveId = evolveId,
            Status = status
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, _settings.TRANSFER_TPTCH_STATUS_URL)
        {
            Content = JsonContent.Create(body, options: _jsonOptions)
        };

        _logger.LogInformation(
            "Calling Transfer tptch/status. EvolveId={EvolveId} Status={Status}", evolveId, status);

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, cancellationToken);
        }
        catch (Exception ex)
        {
            // Best-effort: log and move on. The payment is already settled.
            _logger.LogError(ex,
                "Transfer tptch/status call failed (transport). EvolveId={EvolveId} Status={Status}",
                evolveId, status);
            return;
        }

        if (!response.IsSuccessStatusCode)
        {
            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
            _logger.LogError(
                "Transfer tptch/status returned {StatusCode}. EvolveId={EvolveId} Status={Status} Body={Body}",
                (int)response.StatusCode, evolveId, status, responseBody);
            return;
        }

        _logger.LogInformation(
            "Transfer tptch/status accepted. EvolveId={EvolveId} Status={Status} StatusCode={StatusCode}",
            evolveId, status, (int)response.StatusCode);
    }
}

/// <summary>Body posted to Transfer's /api/tptch/status.</summary>
public sealed class TptchStatusRequest
{
    public string EvolveId { get; set; } = string.Empty;

    /// <summary>"COMPLETED" or "FAILED".</summary>
    public string Status { get; set; } = string.Empty;
}





using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace PaymentServices.Transfer.Functions;

/// <summary>
/// HTTP endpoint: POST /api/tptch/status
///
/// Called by RTPSend's HandlePaymentOutcome after the TabaPay call resolves:
///   - "COMPLETED" when TabaPay succeeds
///   - "FAILED"    only on a TERMINAL (non-retryable) TabaPay failure —
///                 retryable failures are NOT reported here, since the payment
///                 is still being retried and hasn't finally failed.
///
/// PLACEHOLDER: currently logs the status only. Wire up real handling (e.g.
/// patching the tchSendTransactions doc) when the downstream behaviour is defined.
///
/// Auth: Azure Functions key (AuthLevel.Function → x-functions-key), matching
/// the Gateway tptch/send call pattern.
/// </summary>
public sealed class TptchStatusFunction
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly ILogger<TptchStatusFunction> _logger;

    public TptchStatusFunction(ILogger<TptchStatusFunction> logger) => _logger = logger;

    [Function(nameof(TptchStatusFunction))]
    public async Task<HttpResponseData> RunAsync(
        [HttpTrigger(AuthLevel.Function, "post", Route = "tptch/status")] HttpRequestData req,
        CancellationToken cancellationToken)
    {
        TptchStatusRequest? request;

        try
        {
            var body = await new StreamReader(req.Body).ReadToEndAsync(cancellationToken);
            request = JsonSerializer.Deserialize<TptchStatusRequest>(body, JsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "tptch/status: could not parse request body.");
            return await BadRequest(req, "Invalid JSON body.", cancellationToken);
        }

        if (request is null ||
            string.IsNullOrWhiteSpace(request.EvolveId) ||
            string.IsNullOrWhiteSpace(request.Status))
        {
            _logger.LogWarning("tptch/status: missing evolveId or status.");
            return await BadRequest(req, "evolveId and status are required.", cancellationToken);
        }

        // PLACEHOLDER — log only. Downstream handling TBD.
        _logger.LogInformation(
            "tptch/status received. EvolveId={EvolveId} Status={Status}",
            request.EvolveId, request.Status);

        var response = req.CreateResponse(HttpStatusCode.OK);
        await response.WriteAsJsonAsync(
            new { evolveId = request.EvolveId, status = request.Status, received = true },
            cancellationToken);
        return response;
    }

    private static async Task<HttpResponseData> BadRequest(
        HttpRequestData req, string message, CancellationToken cancellationToken)
    {
        var response = req.CreateResponse(HttpStatusCode.BadRequest);
        await response.WriteAsJsonAsync(new { error = message }, cancellationToken);
        return response;
    }
}

/// <summary>Body of a POST to /api/tptch/status.</summary>
public sealed class TptchStatusRequest
{
    [JsonPropertyName("evolveId")]
    public string? EvolveId { get; set; }

    /// <summary>"COMPLETED" or "FAILED".</summary>
    [JsonPropertyName("status")]
    public string? Status { get; set; }
}
