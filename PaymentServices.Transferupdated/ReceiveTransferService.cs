using Microsoft.Extensions.Logging;
using PaymentServices.Transfer.Models;

namespace PaymentServices.Transfer.Services;

/// <summary>
/// Input/progress context for an inbound RTP receive. A deliberately small,
/// Transfer-owned type — the receive path never has (or needs) a full
/// PaymentMessage, which carries required members that only exist in the send
/// pipeline (TaxId, Source, Destination).
/// </summary>
public sealed class ReceiveTransferContext
{
    public string EvolveId { get; init; } = string.Empty;
    public string FintechId { get; init; } = string.Empty;
    public string CorrelationId { get; init; } = string.Empty;
    public string FboAccount { get; init; } = string.Empty;
    public string Amount { get; init; } = string.Empty;
    public string? RemittanceInformation { get; init; }

    // Per-stage progress flags — mirror PaymentMessage's
    // LimitPassed / ScreeningPassed / LedgerPosted contract with RTPSend.
    public bool LimitPassed { get; set; }
    public bool ScreeningPassed { get; set; }
    public bool LedgerPosted { get; set; }

    // Ledger entry pointer, set after the credit posts.
    public string? LedgerEntryId { get; set; }
    public string? LedgerId { get; set; }
}

public interface IReceiveTransferService
{
    Task<TransferResult> ExecuteAsync(
        ReceiveTransferContext context,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Runs the checks for an inbound RTP receive (called synchronously by
/// RTPReceive via POST /tptch/receive):
///   1. LIMIT check ("Receive" category)
///   2. SCREENING check (keyword screen on remittance information)
///   3. LEDGER destination credit via the Evolve NuGet (positive entry, no NSF)
///
/// As each stage passes it sets the corresponding progress flag on the context
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
        ReceiveTransferContext context,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Receive transfer executing. EvolveId={EvolveId} Amount={Amount} FintechId={FintechId}",
            context.EvolveId, context.Amount, context.FintechId);

        // ---- LIMIT ("Receive" category) -----------------------------------
        var limit = await _limitService.CheckAsync(
            context.EvolveId, context.FboAccount, context.Amount,
            LimitCategories.Receive, cancellationToken);
        if (!limit.Allowed)
        {
            throw new LimitExceededException(limit.Reason ?? "Limit check denied");
        }
        context.LimitPassed = true;

        // ---- SCREENING ----------------------------------------------------
        var screening = await _screeningService.CheckTextAsync(
            context.EvolveId, context.RemittanceInformation, cancellationToken);
        if (!screening.Allowed)
        {
            throw new ScreeningRejectedException(screening.Reason ?? "Screening rejected");
        }
        context.ScreeningPassed = true;

        // ---- LEDGER (destination credit) ----------------------------------
        // No NSF concept for an inbound credit. Failures here are unexpected
        // (ledger not found, write failed) and surface as InvalidOperationException.
        var ledgerResult = await _ledgerService.CreditAsync(new LedgerCreditRequest
        {
            EvolveId = context.EvolveId,
            FintechId = context.FintechId,
            CorrelationId = context.CorrelationId,
            FboAccountNumber = context.FboAccount,
            Amount = context.Amount
        }, cancellationToken);

        if (!ledgerResult.Success)
        {
            throw new InvalidOperationException(
                ledgerResult.Reason ?? "Ledger credit failed");
        }
        context.LedgerPosted = true;

        // Ledger entry pointer (id + partition key), for later tptch/status use.
        context.LedgerEntryId = ledgerResult.ReservationId;
        context.LedgerId = ledgerResult.LedgerId;

        _logger.LogInformation(
            "Receive transfer ledger credit complete. EvolveId={EvolveId} LedgerEntryId={LedgerEntryId} LedgerId={LedgerId}",
            context.EvolveId, ledgerResult.ReservationId, ledgerResult.LedgerId);

        return new TransferResult
        {
            GluIdSource = null,                          // credit only
            GluIdDestination = ledgerResult.ReservationId,
            EveTransactionId = context.EvolveId,
            LedgerEntryId = ledgerResult.ReservationId,
            LedgerId = ledgerResult.LedgerId
        };
    }
}
