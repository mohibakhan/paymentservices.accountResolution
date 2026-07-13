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
///   - "COMPLETED" when TabaPay succeeds (first attempt or on a retry)
///   - "FAILED"    on a TERMINAL TabaPay failure (non-retryable, or retries
///                 exhausted). Not called while a payment is still being retried.
///
/// Updates the source-debit ledger entry's status. RTPSend supplies the entry
/// pointer (ledgerEntryId + ledgerId) that Transfer produced when it posted the
/// debit, so this is a POINT PATCH (id + partition key) — no query, no scan of
/// the ledger partition (which grows unboundedly for a given FBO account).
///
/// NOTE — we deliberately do NOT use the ledger NuGet's UpdateEntryStatusAsync:
///   1. It queries for the entry by an id we already have (wasted RU), and
///   2. it reads the results as `dynamic`, which throws RuntimeBinderException
///      under the System.Text.Json serializer that the camelCase ledger docs
///      require ("'JsonElement' does not contain a definition for 'id'").
/// This performs the same two patches directly, with no query and no
/// deserialization of the entry, so the serializer is irrelevant.
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

        // Basic validation — all four fields are required to do the point patch.
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
