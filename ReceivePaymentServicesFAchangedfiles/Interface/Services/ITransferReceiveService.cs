using System.Threading.Tasks;
using Evolve.Digital.Shared.Models.Payments;

namespace ReceivePaymentServicesFA.Interface.Services;

public interface ITransferReceiveService
{
    /// <summary>
    /// Calls Transfer's tptch/receive endpoint (limits, screening and ledger
    /// credit) and records the per-stage LIMIT/SCREENING/LEDGER statuses on the
    /// cosmos document — the receive-side replacement for the prefund-ledger
    /// fraud/sanctions check.
    /// </summary>
    Task<EvolvePaymentRequest> PerformReceiveTransfer(EvolvePaymentRequest cosmosDocument);
}
