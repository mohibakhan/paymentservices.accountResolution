using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Evolve.Digital.Shared.Models.Payments;
using ReceivePaymentServicesFA.Services.Facade.SubSystems;

namespace ReceivePaymentServicesFA.Services.Facade;

public class PreRtpChecksFacade : IPreRtpChecksFacade
{
    private readonly CounterPartySystem _counterPartySystem;
    private readonly PartnerLedgerSystem _partnerLedgerSystem;
    private readonly TransferSystem _transferSystem;
    private readonly ILogger<PreRtpChecksFacade> _logger;

    public PreRtpChecksFacade(CounterPartySystem counterPartySystem,
        PartnerLedgerSystem partnerLedgerSystem,
        TransferSystem transferSystem,
        ILogger<PreRtpChecksFacade> logger)
    {
        _counterPartySystem = counterPartySystem;
        _partnerLedgerSystem = partnerLedgerSystem;
        _transferSystem = transferSystem;
        _logger = logger;
    }

    public async Task<EvolvePaymentRequest> PerformPreRtpChecks(EvolvePaymentRequest request, bool isReturnPayment)
    {
        _logger.LogInformation("Performing operations using the facade.");

        // Counter party lookup
        request = await _counterPartySystem.CounterPartyLookUpAsync(request);

        // Call Partner ledger
        request = await _partnerLedgerSystem.PerformAccountLookupUpdate(request);

        // Call Transfer (tptch/receive) — limits, screening and ledger credit
        if (!isReturnPayment)
            request = await _transferSystem.PerformReceiveTransfer(request);

        return request;
    }
}

public interface IPreRtpChecksFacade
{
    Task<EvolvePaymentRequest> PerformPreRtpChecks(EvolvePaymentRequest request, bool isReturnPayment);
}