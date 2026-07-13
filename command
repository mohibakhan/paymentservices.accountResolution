using Evolve.Digital.LedgerService.Shared.Internal;
using Evolve.Digital.LedgerService.Shared.Internal.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Logging;
using PaymentServices.Transfer.Exceptions;

namespace PaymentServices.Transfer.Services;

/// <summary>Request to reserve (debit) funds on the source ledger.</summary>
public sealed class LedgerReservationRequest
{
    public string EvolveId { get; init; } = string.Empty;
    public string FintechId { get; init; } = string.Empty;
    public string CorrelationId { get; init; } = string.Empty;
    public string FboAccountNumber { get; init; } = string.Empty;
    public string Amount { get; init; } = string.Empty;
}

public sealed class LedgerReservationResult
{
    public bool Success { get; init; }

    /// <summary>
    /// The ledgerEntries document id (what AddEntryAsync returns). Together with
    /// <see cref="LedgerId"/> this is the point key for updating the entry later
    /// (ILedgerInternalClient.UpdateEntryStatusAsync).
    /// </summary>
    public string? ReservationId { get; init; }

    /// <summary>The ledger's id — the ledgerEntries partition key.</summary>
    public string? LedgerId { get; init; }

    public string? Reason { get; init; }

    public static LedgerReservationResult Ok(string reservationId, string ledgerId) =>
        new() { Success = true, ReservationId = reservationId, LedgerId = ledgerId };

    public static LedgerReservationResult Failed(string reason) =>
        new() { Success = false, Reason = reason };
}

/// <summary>
/// Ledger operations backed by the Evolve.Digital.LedgerService NuGet: resolve the
/// source ledger by account number, NSF-check, then post a single negative
/// (debit) entry. Source debit only — no destination credit.
/// </summary>
public interface ILedgerService
{
    Task<LedgerReservationResult> ReserveAsync(LedgerReservationRequest request, CancellationToken cancellationToken = default);
}

public sealed class EvolveLedgerService : ILedgerService
{
    private const string LedgerEntryKind = "tptch.send";

    private readonly ILedgerInternalClient _ledgerClient;
    private readonly ILogger<EvolveLedgerService> _logger;

    public EvolveLedgerService(
        ILedgerInternalClient ledgerClient,
        ILogger<EvolveLedgerService> logger)
    {
        _ledgerClient = ledgerClient;
        _logger = logger;
    }

    public async Task<LedgerReservationResult> ReserveAsync(
        LedgerReservationRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!decimal.TryParse(request.Amount, out var amountDecimal))
        {
            _logger.LogError("Invalid amount '{Amount}' for evolveId {EvolveId}",
                request.Amount, request.EvolveId);
            return LedgerReservationResult.Failed($"Amount '{request.Amount}' is not a valid decimal");
        }

        var ledger = await _ledgerClient.GetLedgerByAccountAsync(request.FboAccountNumber);
        if (ledger is null)
        {
            _logger.LogError(
                "Ledger not found for source account {AccountNumber} (evolveId {EvolveId})",
                request.FboAccountNumber, request.EvolveId);
            return LedgerReservationResult.Failed($"Ledger not found for account {request.FboAccountNumber}");
        }

        var nsf = await _ledgerClient.CheckNsfAsync(ledger.id, amountDecimal);
        if (nsf.ProjectedBalance < 0)
        {
            _logger.LogWarning(
                "Insufficient funds on ledger {LedgerId} (evolveId {EvolveId}): balance={Balance}, requested={Amount}, projected={Projected}",
                ledger.id, request.EvolveId, nsf.Balance, amountDecimal, nsf.ProjectedBalance);

            throw new InsufficientFundsException(
                currentBalance: nsf.Balance,
                requestedAmount: amountDecimal,
                projectedBalance: nsf.ProjectedBalance,
                message: $"Insufficient funds on account {request.FboAccountNumber}: " +
                         $"balance {nsf.Balance:F2}, requested {amountDecimal:F2}");
        }

        var metadata = new Dictionary<string, object>
        {
            { "gluId", Guid.NewGuid().ToString() },
            { "Account", request.FboAccountNumber },
            { "evolveId", request.EvolveId },
            { "correlationId", request.CorrelationId },
            { "fintechId", request.FintechId },
            { "endpoint", "tptch.send" }
        };

        var addEntryRequest = new AddEntryRequest(
            LedgerId: ledger.id,
            Amount: -amountDecimal,           // debit — negative
            Trace: new { evolveId = request.EvolveId },
            Kind: LedgerEntryKind,
            Metadata: metadata,
            IsRemoteAccount: false);

        try
        {
            // AddEntryAsync returns the created ledgerEntries document's id.
            var entryId = await _ledgerClient.AddEntryAsync(addEntryRequest);

            _logger.LogInformation(
                "Ledger entry {EntryId} posted on ledger {LedgerId} for evolveId {EvolveId} amount {Amount}",
                entryId, ledger.id, request.EvolveId, -amountDecimal);

            // Return BOTH the entry id and the ledger id — together they are the
            // point key (id + partition key) used later by tptch/status to update
            // the entry's status via ILedgerInternalClient.UpdateEntryStatusAsync.
            return LedgerReservationResult.Ok(entryId, ledger.id);
        }
        catch (CosmosException cex)
        {
            _logger.LogError(
                "CosmosException posting ledger debit: StatusCode={Status} SubStatus={SubStatus} ActivityId={Activity} Message={Message}",
                cex.StatusCode, cex.SubStatusCode, cex.ActivityId, cex.Message);
            return LedgerReservationResult.Failed($"Ledger write failed: {cex.StatusCode}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "Failed to post ledger entry for evolveId {EvolveId} on ledger {LedgerId}",
                request.EvolveId, ledger.id);
            return LedgerReservationResult.Failed($"AddEntry failed on ledger {ledger.id}: {ex.Message}");
        }
    }
}





using Microsoft.Extensions.Logging;
using PaymentServices.Shared.Messages;
using PaymentServices.Transfer.Exceptions;
using PaymentServices.Transfer.Models;

namespace PaymentServices.Transfer.Services;

public interface ITransferService
{
    Task<TransferResult> ExecuteAsync(
        PaymentMessage message,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Runs the checks for a transfer:
///   1. LIMIT check
///   2. SCREENING check
///   3. LEDGER source debit via the Evolve NuGet (NSF terminal)
///
/// As each stage passes it sets the corresponding progress flag on the message
/// (LimitPassed / ScreeningPassed / LedgerPosted), so a failure carries accurate
/// partial progress for RTPSend's per-stage history.
///
/// After the ledger debit it also records the ledger entry pointer on the message
/// (LedgerEntryId + LedgerId). RTPSend passes these back to Transfer's tptch/status
/// endpoint, which uses them to update the entry's status once TabaPay resolves.
///
/// Destination credit is intentionally NOT performed (source debit only).
/// </summary>
public sealed class TransferService : ITransferService
{
    private readonly ILimitService _limitService;
    private readonly IScreeningService _screeningService;
    private readonly ILedgerService _ledgerService;
    private readonly ILogger<TransferService> _logger;

    public TransferService(
        ILimitService limitService,
        IScreeningService screeningService,
        ILedgerService ledgerService,
        ILogger<TransferService> logger)
    {
        _limitService = limitService;
        _screeningService = screeningService;
        _ledgerService = ledgerService;
        _logger = logger;
    }

    public async Task<TransferResult> ExecuteAsync(
        PaymentMessage message,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Transfer executing. EvolveId={EvolveId} Amount={Amount} FintechId={FintechId}",
            message.EvolveId, message.Amount, message.FintechId);

        // ---- LIMIT --------------------------------------------------------
        var limit = await _limitService.CheckAsync(message, cancellationToken);
        if (!limit.Allowed)
        {
            throw new LimitExceededException(limit.Reason ?? "Limit check denied");
        }
        message.LimitPassed = true;

        // ---- SCREENING ----------------------------------------------------
        var screening = await _screeningService.CheckAsync(message, cancellationToken);
        if (!screening.Allowed)
        {
            throw new ScreeningRejectedException(screening.Reason ?? "Screening rejected");
        }
        message.ScreeningPassed = true;

        // ---- LEDGER (source debit) ---------------------------------------
        // NSF throws InsufficientFundsException (terminal). Other failures
        // return a Failed result which we turn into a retryable exception.
        var ledgerResult = await _ledgerService.ReserveAsync(new LedgerReservationRequest
        {
            EvolveId = message.EvolveId,
            FintechId = message.FintechId,
            CorrelationId = message.CorrelationId,
            FboAccountNumber = message.FboAccount ?? string.Empty,
            Amount = message.Amount
        }, cancellationToken);

        if (!ledgerResult.Success)
        {
            throw new InvalidOperationException(
                ledgerResult.Reason ?? "Ledger reservation failed");
        }
        message.LedgerPosted = true;

        // Ledger entry pointer (id + partition key). Carried on the message so
        // RTPSend can hand it back to tptch/status, which updates the entry's
        // status once TabaPay resolves — no lookup/scan needed anywhere.
        message.LedgerEntryId = ledgerResult.ReservationId;
        message.LedgerId = ledgerResult.LedgerId;

        _logger.LogInformation(
            "Transfer ledger debit complete. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId} LedgerId={LedgerId}",
            message.EvolveId, ledgerResult.ReservationId, ledgerResult.LedgerId);

        return new TransferResult
        {
            GluIdSource = ledgerResult.ReservationId,
            GluIdDestination = null,           // source debit only
            EveTransactionId = message.EvolveId,
            LedgerEntryId = ledgerResult.ReservationId,
            LedgerId = ledgerResult.LedgerId
        };
    }
}

/// <summary>Terminal — limit check denied the transfer.</summary>
public sealed class LimitExceededException : Exception
{
    public LimitExceededException(string message) : base(message) { }
}

/// <summary>Terminal — screening/compliance rejected the transfer.</summary>
public sealed class ScreeningRejectedException : Exception
{
    public ScreeningRejectedException(string message) : base(message) { }
}





using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using Evolve.Digital.LedgerService.Shared.Internal;
using Evolve.Digital.LedgerService.Shared.Internal.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace PaymentServices.Transfer.Functions;

/// <summary>
/// HTTP Trigger — POST /tptch/status. Called by RTPSend once the TabaPay outcome
/// is final:
///   - "COMPLETED" when TabaPay succeeds
///   - "FAILED"    only on a TERMINAL (non-retryable) TabaPay failure — retryable
///                 failures are NOT reported, since the payment is still being
///                 retried and hasn't finally failed.
///
/// Updates the source-debit ledger entry's status via the ledger NuGet. The
/// caller supplies the entry pointer (ledgerEntryId + ledgerId), which Transfer
/// originally produced and RTPSend carried on the outcome message — so this is a
/// point update (id + partition key), not a scan of the ledger partition.
///
/// The ledger update lives here (not in RTPSend) because Transfer already owns
/// ledger access; RTPSend stays ledger-free.
/// </summary>
public sealed class TptchStatusFunction
{
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly ILedgerInternalClient _ledgerClient;
    private readonly ILogger<TptchStatusFunction> _logger;

    public TptchStatusFunction(
        ILedgerInternalClient ledgerClient,
        ILogger<TptchStatusFunction> logger)
    {
        _ledgerClient = ledgerClient;
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

        // Basic validation
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
            // Point update: ledgerId is the partition key, ledgerEntryId is the doc id.
            await _ledgerClient.UpdateEntryStatusAsync(new UpdateEntryStatusRequest(
                LedgerId: request.LedgerId,
                EntryId: request.LedgerEntryId,
                Status: request.Status));

            _logger.LogInformation(
                "Ledger entry status updated. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId} Status={Status}",
                request.EvolveId, request.LedgerEntryId, request.Status);

            return req.CreateResponse(HttpStatusCode.OK);
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

    /// <summary>The ledgerEntries document id (point key).</summary>
    [JsonPropertyName("ledgerEntryId")]
    public string? LedgerEntryId { get; set; }

    /// <summary>The ledgerEntries partition key (the ledger's id).</summary>
    [JsonPropertyName("ledgerId")]
    public string? LedgerId { get; set; }
}
