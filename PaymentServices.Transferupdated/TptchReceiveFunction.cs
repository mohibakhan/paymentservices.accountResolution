using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using PaymentServices.Transfer.Services;

namespace PaymentServices.Transfer.Functions;

/// <summary>
/// HTTP Trigger — POST /tptch/receive. Called SYNCHRONOUSLY by RTPReceive while
/// it is still holding TabaPay's HTTP request (no Service Bus, no account
/// resolution on the receive side — the partner-ledger lookup has already
/// resolved the FBO account before this call).
///
/// Runs LIMIT ("Receive" category) → SCREENING → LEDGER (FBO destination
/// credit, positive entry, no NSF).
///
/// Responses (always JSON):
///   200 status=COMPLETED — all three stages passed; carries gluId + the
///       ledger entry pointer (ledgerEntryId + ledgerId).
///   200 status=REJECTED  — a business rejection (limit or screening); carries
///       failedStage + reason + the per-stage flags. 200 because the pipeline
///       ran and produced a terminal business answer.
///   400 — invalid/missing request fields.
///   500 status=FAILED    — unexpected error (ledger write failed etc.).
///
/// The per-stage flags (limitPassed / screeningPassed / ledgerPosted) become
/// LIMIT/SCREENING/LEDGER statusHistory entries on RTPReceive's payment doc —
/// the same granular history RTPSend writes from Transfer's outcome message.
/// </summary>
public sealed class TptchReceiveFunction
{
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly IReceiveTransferService _receiveTransferService;
    private readonly ILogger<TptchReceiveFunction> _logger;

    public TptchReceiveFunction(
        IReceiveTransferService receiveTransferService,
        ILogger<TptchReceiveFunction> logger)
    {
        _receiveTransferService = receiveTransferService;
        _logger = logger;
    }

    [Function(nameof(TptchReceiveFunction))]
    public async Task<HttpResponseData> RunAsync(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "tptch/receive")]
        HttpRequestData req,
        CancellationToken cancellationToken)
    {
        TptchReceiveRequest? request;
        try
        {
            request = await JsonSerializer.DeserializeAsync<TptchReceiveRequest>(
                req.Body, _jsonOptions, cancellationToken);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning("tptch/receive: invalid JSON. {Error}", ex.Message);
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }

        // validation
        if (request is null ||
            string.IsNullOrWhiteSpace(request.EvolveId) ||
            string.IsNullOrWhiteSpace(request.FboAccount) ||
            string.IsNullOrWhiteSpace(request.Amount))
        {
            _logger.LogWarning("tptch/receive: evolveId, fboAccount and amount are all required.");
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }

        _logger.LogInformation(
            "tptch/receive received. EvolveId={EvolveId} FintechId={FintechId} Amount={Amount}",
            request.EvolveId, request.FintechId, request.Amount);

        var context = new ReceiveTransferContext
        {
            EvolveId = request.EvolveId,
            CorrelationId = request.CorrelationId ?? request.EvolveId,
            FintechId = request.FintechId ?? string.Empty,
            FboAccount = request.FboAccount,
            Amount = request.Amount,
            RemittanceInformation = request.RemittanceInformation
        };

        try
        {
            var result = await _receiveTransferService.ExecuteAsync(context, cancellationToken);

            _logger.LogInformation(
                "tptch/receive completed. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId}",
                request.EvolveId, result.LedgerEntryId);

            return await WriteResponseAsync(req, HttpStatusCode.OK, new TptchReceiveResponse
            {
                EvolveId = request.EvolveId,
                Status = TptchReceiveResponse.Completed,
                LimitPassed = true,
                ScreeningPassed = true,
                LedgerPosted = true,
                GluId = result.GluIdDestination,
                LedgerEntryId = result.LedgerEntryId,
                LedgerId = result.LedgerId,
                EveTransactionId = result.EveTransactionId
            }, cancellationToken);
        }
        catch (Exception ex) when (
            ex is LimitExceededException or ScreeningRejectedException)
        {
            // TERMINAL business rejection — the pipeline ran and said no.
            var failedStage = context.LimitPassed ? "SCREENING" : "LIMIT";

            _logger.LogWarning(ex,
                "tptch/receive rejected. EvolveId={EvolveId} Stage={Stage} Reason={Reason}",
                request.EvolveId, failedStage, ex.Message);

            return await WriteResponseAsync(req, HttpStatusCode.OK, new TptchReceiveResponse
            {
                EvolveId = request.EvolveId,
                Status = TptchReceiveResponse.Rejected,
                LimitPassed = context.LimitPassed,
                ScreeningPassed = context.ScreeningPassed,
                LedgerPosted = false,
                FailedStage = failedStage,
                Reason = ex.Message
            }, cancellationToken);
        }
        catch (Exception ex)
        {
            // UNEXPECTED — ledger write failure or anything else.
            var failedStage = !context.LimitPassed ? "LIMIT"
                : !context.ScreeningPassed ? "SCREENING"
                : "LEDGER";

            _logger.LogError(ex,
                "tptch/receive failed. EvolveId={EvolveId} Stage={Stage}",
                request.EvolveId, failedStage);

            return await WriteResponseAsync(req, HttpStatusCode.InternalServerError, new TptchReceiveResponse
            {
                EvolveId = request.EvolveId,
                Status = TptchReceiveResponse.Failed,
                LimitPassed = context.LimitPassed,
                ScreeningPassed = context.ScreeningPassed,
                LedgerPosted = context.LedgerPosted,
                FailedStage = failedStage,
                Reason = ex.Message
            }, cancellationToken);
        }
    }

    private static async Task<HttpResponseData> WriteResponseAsync(
        HttpRequestData req,
        HttpStatusCode statusCode,
        TptchReceiveResponse body,
        CancellationToken cancellationToken)
    {
        var response = req.CreateResponse(statusCode);
        response.Headers.Add("Content-Type", "application/json; charset=utf-8");
        await response.WriteStringAsync(JsonSerializer.Serialize(body, _jsonOptions));
        return response;
    }
}

/// <summary>Body of POST /tptch/receive.</summary>
public sealed class TptchReceiveRequest
{
    [JsonPropertyName("evolveId")]
    public string? EvolveId { get; set; }

    [JsonPropertyName("fintechId")]
    public string? FintechId { get; set; }

    [JsonPropertyName("correlationId")]
    public string? CorrelationId { get; set; }

    /// <summary>The FBO account number resolved by RTPReceive's partner-ledger lookup.</summary>
    [JsonPropertyName("fboAccount")]
    public string? FboAccount { get; set; }

    [JsonPropertyName("amount")]
    public string? Amount { get; set; }

    /// <summary>Optional remittance text — screened when present.</summary>
    [JsonPropertyName("remittanceInformation")]
    public string? RemittanceInformation { get; set; }
}

/// <summary>Body returned by POST /tptch/receive.</summary>
public sealed class TptchReceiveResponse
{
    public const string Completed = "COMPLETED";
    public const string Rejected = "REJECTED";
    public const string Failed = "FAILED";

    [JsonPropertyName("evolveId")]
    public string? EvolveId { get; set; }

    /// <summary>"COMPLETED", "REJECTED" (business) or "FAILED" (unexpected).</summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = Failed;

    [JsonPropertyName("limitPassed")]
    public bool LimitPassed { get; set; }

    [JsonPropertyName("screeningPassed")]
    public bool ScreeningPassed { get; set; }

    [JsonPropertyName("ledgerPosted")]
    public bool LedgerPosted { get; set; }

    /// <summary>"LIMIT", "SCREENING" or "LEDGER" when not COMPLETED.</summary>
    [JsonPropertyName("failedStage")]
    public string? FailedStage { get; set; }

    [JsonPropertyName("reason")]
    public string? Reason { get; set; }

    /// <summary>GluId of the destination credit entry.</summary>
    [JsonPropertyName("gluId")]
    public string? GluId { get; set; }

    /// <summary>The ledgerEntries document id (the point key).</summary>
    [JsonPropertyName("ledgerEntryId")]
    public string? LedgerEntryId { get; set; }

    /// <summary>The ledgerEntries partition key (the ledger's id).</summary>
    [JsonPropertyName("ledgerId")]
    public string? LedgerId { get; set; }

    [JsonPropertyName("eveTransactionId")]
    public string? EveTransactionId { get; set; }
}
