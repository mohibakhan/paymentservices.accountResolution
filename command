public class TabaPayProcessingException : Exception
{
    /// <summary>
    /// True when the failure is worth retrying (5xx, timeout, network). False for
    /// deterministic failures (4xx validation, hard declines) that would fail
    /// identically on every retry — those are dead-lettered rather than redelivered.
    /// Defaults to true so callers that don't classify keep the old retry behaviour.
    /// </summary>
    public bool IsRetryable { get; }

    /// <summary>TabaPay HTTP status when the failure came from a response; null for transport faults.</summary>
    public HttpStatusCode? StatusCode { get; }

    public TabaPayProcessingException(string message, bool isRetryable = true, HttpStatusCode? statusCode = null)
        : base(message)
    {
        IsRetryable = isRetryable;
        StatusCode = statusCode;
    }

    public TabaPayProcessingException(string message, Exception? inner, bool isRetryable = true, HttpStatusCode? statusCode = null)
        : base(message, inner)
    {
        IsRetryable = isRetryable;
        StatusCode = statusCode;
    }
}
