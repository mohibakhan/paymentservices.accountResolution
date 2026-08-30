using Newtonsoft.Json;

namespace ReceivePaymentServicesFA.Models.Response;

/// <summary>Body returned by Transfer's POST /tptch/receive.</summary>
public class TransferReceiveResponse
{
    public const string StatusCompleted = "COMPLETED";
    public const string StatusRejected = "REJECTED";
    public const string StatusFailed = "FAILED";

    [JsonProperty("evolveId")]
    public string EvolveId { get; set; }

    /// <summary>"COMPLETED", "REJECTED" (business) or "FAILED" (unexpected).</summary>
    [JsonProperty("status")]
    public string Status { get; set; }

    [JsonProperty("limitPassed")]
    public bool LimitPassed { get; set; }

    [JsonProperty("screeningPassed")]
    public bool ScreeningPassed { get; set; }

    [JsonProperty("ledgerPosted")]
    public bool LedgerPosted { get; set; }

    /// <summary>"LIMIT", "SCREENING" or "LEDGER" when not COMPLETED.</summary>
    [JsonProperty("failedStage")]
    public string FailedStage { get; set; }

    [JsonProperty("reason")]
    public string Reason { get; set; }

    /// <summary>GluId of the destination credit entry.</summary>
    [JsonProperty("gluId")]
    public string GluId { get; set; }

    /// <summary>The ledgerEntries document id (the point key).</summary>
    [JsonProperty("ledgerEntryId")]
    public string LedgerEntryId { get; set; }

    /// <summary>The ledgerEntries partition key (the ledger's id).</summary>
    [JsonProperty("ledgerId")]
    public string LedgerId { get; set; }

    [JsonProperty("eveTransactionId")]
    public string EveTransactionId { get; set; }
}
