using System;

namespace ReceivePaymentServicesFA.Exceptions;

/// <summary>
/// Thrown when the Transfer tptch/receive call does not complete.
/// <see cref="IsBusinessRejection"/> distinguishes a terminal business
/// rejection (limit / screening denied — mapped to a TabaPay AC06 REJECTED
/// response) from an unexpected failure (mapped to a 500).
/// </summary>
[Serializable]
internal class TransferException : Exception
{
    /// <summary>True when Transfer rejected the payment on business grounds (limit/screening).</summary>
    public bool IsBusinessRejection { get; }

    /// <summary>"LIMIT", "SCREENING" or "LEDGER" when known.</summary>
    public string FailedStage { get; }

    public TransferException()
    {
    }

    public TransferException(string message) : base(message)
    {
    }

    public TransferException(string message, Exception innerException) : base(message, innerException)
    {
    }

    public TransferException(string message, bool isBusinessRejection, string failedStage) : base(message)
    {
        IsBusinessRejection = isBusinessRejection;
        FailedStage = failedStage;
    }
}
