using Microsoft.Extensions.Logging;
using PaymentServices.Shared.Messages;
using PaymentServices.Transfer.Models;

namespace PaymentServices.Transfer.Services;

public interface IReceiveTransferService
{
    Task<TransferResult> ExecuteAsync(
        PaymentMessage message,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Runs the checks for an inbound RTP receive (called synchronously by
/// RTPReceive via POST /tptch/receive):
///   1. LIMIT check ("Receive" category)
///   2. SCREENING check (keyword screen on remittance information)
///   3. LEDGER destination credit via the Evolve NuGet (positive entry, no NSF)
///
/// As each stage passes it sets the corresponding progress flag on the message
/// (LimitPassed / ScreeningPassed / LedgerPosted), so a failure carries accurate
/// partial progress for RTPReceive's per-stage statusHistory — the same contract
/// TransferService has with RTPSend.
///
/// After the credit it records the ledger entry pointer (LedgerEntryId +
/// LedgerId) so RTPReceive can persist it and hand it back to tptch/status once
/// the TCH outcome is final.
/// </summary>
public sealed class ReceiveTransferService : IReceiveTransferService
{
    private readonly ILimitService _limitService;
    private readonly IScreeningService _screeningService;
    private readonly ILedgerService _ledgerService;
    private readonly ILogger<ReceiveTransferService> _logger;

    public ReceiveTransferService(
        ILimitService limitService,
        IScreeningService screeningService,
        ILedgerService ledgerService,
        ILogger<ReceiveTransferService> logger)
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
            "Receive transfer executing. EvolveId={EvolveId} Amount={Amount} FintechId={FintechId}",
            message.EvolveId, message.Amount, message.FintechId);

        // ---- LIMIT ("Receive" category) -----------------------------------
        var limit = await _limitService.CheckAsync(
            message, LimitCategories.Receive, cancellationToken);
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

        // ---- LEDGER (destination credit) ----------------------------------
        // No NSF concept for an inbound credit. Failures here are unexpected
        // (ledger not found, write failed) and surface as InvalidOperationException.
        var ledgerResult = await _ledgerService.CreditAsync(new LedgerCreditRequest
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
                ledgerResult.Reason ?? "Ledger credit failed");
        }
        message.LedgerPosted = true;

        // Ledger entry pointer (id + partition key), for later tptch/status use.
        message.LedgerEntryId = ledgerResult.ReservationId;
        message.LedgerId = ledgerResult.LedgerId;

        _logger.LogInformation(
            "Receive transfer ledger credit complete. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId} LedgerId={LedgerId}",
            message.EvolveId, ledgerResult.ReservationId, ledgerResult.LedgerId);

        return new TransferResult
        {
            GluIdSource = null,                          // credit only
            GluIdDestination = ledgerResult.ReservationId,
            EveTransactionId = message.EvolveId,
            LedgerEntryId = ledgerResult.ReservationId,
            LedgerId = ledgerResult.LedgerId
        };
    }
}
