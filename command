/// <summary>
/// Result of executing a transfer.
/// </summary>
public sealed class TransferResult
{
    /// <summary>GluId of the RTPPrefund debit entry.</summary>
    public string? GluIdSource { get; init; }

    /// <summary>GluId of the destination credit entry.</summary>
    public string? GluIdDestination { get; init; }

    public required string EveTransactionId { get; init; }

    /// <summary>
    /// Cosmos id of the ledgerEntries document for the source debit. Together
    /// with <see cref="LedgerId"/> this is the point key used by tptch/status to
    /// update the entry's status once TabaPay resolves.
    /// </summary>
    public string? LedgerEntryId { get; init; }

    /// <summary>The ledgerEntries partition key (the ledger's id).</summary>
    public string? LedgerId { get; init; }
}
