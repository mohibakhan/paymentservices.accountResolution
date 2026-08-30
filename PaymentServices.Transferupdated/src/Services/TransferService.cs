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
        var limit = await _limitService.CheckAsync(message, LimitCategories.Send, cancellationToken);
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