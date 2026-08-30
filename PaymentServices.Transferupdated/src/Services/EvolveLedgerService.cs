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

/// <summary>Request to credit funds on the destination (FBO) ledger — RTP receive.</summary>
public sealed class LedgerCreditRequest
{
    public string EvolveId { get; init; } = string.Empty;
    public string FintechId { get; init; } = string.Empty;
    public string CorrelationId { get; init; } = string.Empty;
    public string FboAccountNumber { get; init; } = string.Empty;
    public string Amount { get; init; } = string.Empty;
}

/// <summary>
/// Ledger operations backed by the Evolve.Digital.LedgerService NuGet.
/// Mirrors the logic previously in RTPSend's EvolveLedgerService: resolve the
/// source ledger by account number, NSF-check, then post a single negative
/// (debit) entry — plus the receive-side mirror: resolve the FBO ledger by
/// account number and post a single positive (credit) entry, no NSF check.
/// </summary>
public interface ILedgerService
{
    Task<LedgerReservationResult> ReserveAsync(LedgerReservationRequest request, CancellationToken cancellationToken = default);

    /// <summary>
    /// Posts a POSITIVE (credit) entry on the FBO ledger for an inbound RTP
    /// receive. No NSF check — funds are coming in. Returns the entry pointer
    /// (entry id + ledger id) so the caller can persist it for later status
    /// updates via tptch/status.
    /// </summary>
    Task<LedgerReservationResult> CreditAsync(LedgerCreditRequest request, CancellationToken cancellationToken = default);
}

public sealed class EvolveLedgerService : ILedgerService
{
    private const string LedgerEntryKind = "tptch.send";
    private const string ReceiveLedgerEntryKind = "tptch.receive";

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

    public async Task<LedgerReservationResult> CreditAsync(
        LedgerCreditRequest request,
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
                "Ledger not found for destination account {AccountNumber} (evolveId {EvolveId})",
                request.FboAccountNumber, request.EvolveId);
            return LedgerReservationResult.Failed($"Ledger not found for account {request.FboAccountNumber}");
        }

        // No NSF check — this is an inbound credit; the balance only goes up.

        var metadata = new Dictionary<string, object>
        {
            { "gluId", Guid.NewGuid().ToString() },
            { "Account", request.FboAccountNumber },
            { "evolveId", request.EvolveId },
            { "correlationId", request.CorrelationId },
            { "fintechId", request.FintechId },
            { "endpoint", ReceiveLedgerEntryKind }
        };

        var addEntryRequest = new AddEntryRequest(
            LedgerId: ledger.id,
            Amount: amountDecimal,            // credit — positive
            Trace: new { evolveId = request.EvolveId },
            Kind: ReceiveLedgerEntryKind,
            Metadata: metadata,
            IsRemoteAccount: false);

        try
        {
            // AddEntryAsync returns the created ledgerEntries document's id.
            var entryId = await _ledgerClient.AddEntryAsync(addEntryRequest);

            _logger.LogInformation(
                "Ledger credit entry {EntryId} posted on ledger {LedgerId} for evolveId {EvolveId} amount {Amount}",
                entryId, ledger.id, request.EvolveId, amountDecimal);

            // Entry id + ledger id together form the point key used later by
            // tptch/status to update the entry's status.
            return LedgerReservationResult.Ok(entryId, ledger.id);
        }
        catch (CosmosException cex)
        {
            _logger.LogError(
                "CosmosException posting ledger credit: StatusCode={Status} SubStatus={SubStatus} ActivityId={Activity} Message={Message}",
                cex.StatusCode, cex.SubStatusCode, cex.ActivityId, cex.Message);
            return LedgerReservationResult.Failed($"Ledger write failed: {cex.StatusCode}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "Failed to post ledger credit entry for evolveId {EvolveId} on ledger {LedgerId}",
                request.EvolveId, ledger.id);
            return LedgerReservationResult.Failed($"AddEntry failed on ledger {ledger.id}: {ex.Message}");
        }
    }
}