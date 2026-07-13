using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace PaymentServices.Transfer.Functions;

/// <summary>
/// HTTP Trigger — POST /tptch/status. Called by RTPSend once the TabaPay outcome
/// is final: "COMPLETED" on success, "FAILED" only on a terminal (non-retryable)
/// failure. Fire-and-forget from the caller's perspective.
///
/// PLACEHOLDER: logs the status. Real handling TBD.
/// </summary>
public sealed class TptchStatusFunction
{
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly ILogger<TptchStatusFunction> _logger;

    public TptchStatusFunction(ILogger<TptchStatusFunction> logger) => _logger = logger;

    [Function(nameof(TptchStatusFunction))]
    public async Task<HttpResponseData> RunAsync(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "tptch/status")]
        HttpRequestData req,
        CancellationToken cancellationToken)
    {
        TptchStatusRequest? request;
        try
        {
            request = await JsonSerializer.DeserializeAsync<TptchStatusRequest>(
                req.Body, _jsonOptions, cancellationToken);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning("tptch/status: invalid JSON. {Error}", ex.Message);
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }

        if (request is null ||
            string.IsNullOrWhiteSpace(request.EvolveId) ||
            string.IsNullOrWhiteSpace(request.Status))
        {
            _logger.LogWarning("tptch/status: evolveId and status are required.");
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }

        _logger.LogInformation(
            "tptch/status received. EvolveId={EvolveId} Status={Status}",
            request.EvolveId, request.Status);

        return req.CreateResponse(HttpStatusCode.OK);
    }
}

/// <summary>Body of POST /tptch/status.</summary>
public sealed class TptchStatusRequest
{
    [JsonPropertyName("evolveId")]
    public string? EvolveId { get; set; }

    /// <summary>"COMPLETED" or "FAILED".</summary>
    [JsonPropertyName("status")]
    public string? Status { get; set; }
}
