namespace ReceivePaymentServicesFA.Constants;

/// <summary>
/// Stage names written to statusHistory by the Transfer (tptch/receive) call —
/// the same granular LIMIT/SCREENING/LEDGER stages RTPSend records from
/// Transfer's outcome message. Kept as strings because statusHistory stages are
/// strings and these values are owned by the PaymentServices.Transfer pipeline,
/// not the Evolve.Digital.Shared RequestStage enum.
/// </summary>
public static class TransferStageConstants
{
    public const string Limit = "LIMIT";
    public const string Screening = "SCREENING";
    public const string Ledger = "LEDGER";

    /// <summary>True when the stage is one of the Transfer pipeline stages.</summary>
    public static bool IsTransferStage(string stage) =>
        stage == Limit || stage == Screening || stage == Ledger;
}
