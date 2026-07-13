"rtpSend:AppSettings:TRANSFER_TPTCH_STATUS_URL": "https://fa-pmtsvc-transfer-dev-centralus.azurewebsites.net/api/tptch/status?code=<transfer-function-key>"

public string? TRANSFER_TPTCH_STATUS_URL { get; set; }


using System.Net.Http.Json;
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
    ///
    /// Best-effort: failures are logged, never thrown — the payment is already
    /// settled and must not be re-processed because a status callback hiccupped.
    /// </summary>
    Task ReportStatusAsync(string evolveId, string status, CancellationToken cancellationToken = default);
}

/// <summary>
/// Typed HttpClient for Transfer's POST /api/tptch/status. Mirrors the
/// GatewayClient pattern: a single config-driven URL with the Azure Functions
/// key embedded as the ?code= query parameter.
/// </summary>
public sealed class TransferStatusClient : ITransferStatusClient
{
    public const string CompletedStatus = "COMPLETED";
    public const string FailedStatus = "FAILED";

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
        var url = _settings.TRANSFER_TPTCH_STATUS_URL;

        if (string.IsNullOrWhiteSpace(url))
        {
            _logger.LogWarning(
                "TRANSFER_TPTCH_STATUS_URL not configured; skipping status callback. " +
                "EvolveId={EvolveId} Status={Status}", evolveId, status);
            return;
        }

        try
        {
            // The function key is embedded in the configured URL (?code=...),
            // so no separate auth header is needed.
            using var response = await _httpClient.PostAsJsonAsync(
                url, new { evolveId, status }, cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(cancellationToken);
                _logger.LogError(
                    "tptch/status callback failed ({StatusCode}). EvolveId={EvolveId} Status={Status} Body={Body}",
                    response.StatusCode, evolveId, status, body);
                return;
            }

            _logger.LogInformation(
                "Reported '{Status}' to Transfer tptch/status. EvolveId={EvolveId}", status, evolveId);
        }
        catch (Exception ex)
        {
            // Best-effort — never fail the payment because the status callback did.
            _logger.LogError(ex,
                "tptch/status callback threw. EvolveId={EvolveId} Status={Status}", evolveId, status);
        }
    }
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
