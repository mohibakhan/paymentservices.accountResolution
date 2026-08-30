using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace PaymentServices.Transfer.Functions;

/// <summary>
/// HTTP Trigger — POST /tptch/status. Called by RTPSend once the TabaPay outcome
/// is FINAL:
///   - "completed"
///   - "failed"  
/// </summary>
public sealed class TptchStatusFunction
{
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly Container _ledgerEntries;
    private readonly ILogger<TptchStatusFunction> _logger;

    public TptchStatusFunction(
        [FromKeyedServices("ledgerEntries")] Container ledgerEntries,
        ILogger<TptchStatusFunction> logger)
    {
        _ledgerEntries = ledgerEntries;
        _logger = logger;
    }

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

        // validation
        if (request is null ||
            string.IsNullOrWhiteSpace(request.EvolveId) ||
            string.IsNullOrWhiteSpace(request.Status) ||
            string.IsNullOrWhiteSpace(request.LedgerEntryId) ||
            string.IsNullOrWhiteSpace(request.LedgerId))
        {
            _logger.LogWarning(
                "tptch/status: evolveId, status, ledgerEntryId and ledgerId are all required.");
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }

        _logger.LogInformation(
            "tptch/status received. EvolveId={EvolveId} Status={Status} LedgerEntryId={LedgerEntryId} LedgerId={LedgerId}",
            request.EvolveId, request.Status, request.LedgerEntryId, request.LedgerId);

        try
        {
            // Point patch: id = ledgerEntryId, partition key = ledgerId.
            var patches = new List<PatchOperation>
            {
                PatchOperation.Set("/status", request.Status),
                PatchOperation.Set("/updatedAt", DateTime.UtcNow)
            };

            await _ledgerEntries.PatchItemAsync<dynamic>(
                id: request.LedgerEntryId,
                partitionKey: new PartitionKey(request.LedgerId),
                patchOperations: patches,
                cancellationToken: cancellationToken);

            _logger.LogInformation(
                "Ledger entry status updated. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId} Status={Status}",
                request.EvolveId, request.LedgerEntryId, request.Status);

            return req.CreateResponse(HttpStatusCode.OK);
        }
        catch (CosmosException cex) when (cex.StatusCode == HttpStatusCode.NotFound)
        {
            _logger.LogError(
                "Ledger entry not found. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId} LedgerId={LedgerId}",
                request.EvolveId, request.LedgerEntryId, request.LedgerId);
            return req.CreateResponse(HttpStatusCode.NotFound);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "Failed to update ledger entry status. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId} Status={Status}",
                request.EvolveId, request.LedgerEntryId, request.Status);
            return req.CreateResponse(HttpStatusCode.InternalServerError);
        }
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

    /// <summary>The ledgerEntries document id (the point key).</summary>
    [JsonPropertyName("ledgerEntryId")]
    public string? LedgerEntryId { get; set; }

    /// <summary>The ledgerEntries partition key (the ledger's id).</summary>
    [JsonPropertyName("ledgerId")]
    public string? LedgerId { get; set; }
}