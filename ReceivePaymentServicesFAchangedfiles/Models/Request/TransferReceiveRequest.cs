using Newtonsoft.Json;

namespace ReceivePaymentServicesFA.Models.Request;

/// <summary>Body posted to Transfer's POST /tptch/receive.</summary>
public class TransferReceiveRequest
{
    [JsonProperty("evolveId")]
    public string EvolveId { get; set; }

    [JsonProperty("fintechId")]
    public string FintechId { get; set; }

    [JsonProperty("correlationId")]
    public string CorrelationId { get; set; }

    /// <summary>The FBO account number resolved by the partner-ledger lookup.</summary>
    [JsonProperty("fboAccount")]
    public string FboAccount { get; set; }

    [JsonProperty("amount")]
    public string Amount { get; set; }

    /// <summary>Optional remittance text — Transfer screens it when present.</summary>
    [JsonProperty("remittanceInformation")]
    public string RemittanceInformation { get; set; }
}
