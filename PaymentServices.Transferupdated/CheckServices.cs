using Microsoft.Extensions.Logging;
using PaymentServices.Shared.Messages;

namespace PaymentServices.Transfer.Services;

/// <summary>Result of a pre-ledger check (limit or screening).</summary>
public sealed class CheckResult
{
    public bool Allowed { get; init; }
    public string? Reason { get; init; }
    public static CheckResult Pass() => new() { Allowed = true };
    public static CheckResult Deny(string reason) => new() { Allowed = false, Reason = reason };
}

/// <summary>Limit categories evaluated by the limits service.</summary>
public static class LimitCategories
{
    public const string Send = "Send";
    public const string Receive = "Receive";
}

/// <summary>Limit check. PLACEHOLDER — swap for the real limits NuGet when available.</summary>
public interface ILimitService
{
    Task<CheckResult> CheckAsync(
        PaymentMessage message,
        string category = LimitCategories.Send,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Primitive overload for callers that have no PaymentMessage (e.g. the
    /// tptch/receive HTTP path).
    /// </summary>
    Task<CheckResult> CheckAsync(
        string evolveId,
        string fboAccount,
        string amount,
        string category,
        CancellationToken cancellationToken = default);
}

/// <summary>Screening/compliance check. PLACEHOLDER — swap for the real screening NuGet.</summary>
public interface IScreeningService
{
    Task<CheckResult> CheckAsync(PaymentMessage message, CancellationToken cancellationToken = default);

    /// <summary>
    /// Primitive overload for callers that have no PaymentMessage (e.g. the
    /// tptch/receive HTTP path). Screens the given remittance text.
    /// </summary>
    Task<CheckResult> CheckTextAsync(
        string evolveId,
        string? remittanceInformation,
        CancellationToken cancellationToken = default);
}

public sealed class NoOpLimitService : ILimitService
{
    private readonly ILogger<NoOpLimitService> _logger;
    public NoOpLimitService(ILogger<NoOpLimitService> logger) => _logger = logger;

    public Task<CheckResult> CheckAsync(
        PaymentMessage message,
        string category = LimitCategories.Send,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "NoOp limit check passed. EvolveId={EvolveId} Category={Category}", message.EvolveId, category);
        return Task.FromResult(CheckResult.Pass());
    }

    public Task<CheckResult> CheckAsync(
        string evolveId,
        string fboAccount,
        string amount,
        string category,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "NoOp limit check passed. EvolveId={EvolveId} Category={Category}", evolveId, category);
        return Task.FromResult(CheckResult.Pass());
    }
}

public sealed class NoOpScreeningService : IScreeningService
{
    private readonly ILogger<NoOpScreeningService> _logger;
    public NoOpScreeningService(ILogger<NoOpScreeningService> logger) => _logger = logger;

    public Task<CheckResult> CheckAsync(PaymentMessage message, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("NoOp screening check passed. EvolveId={EvolveId}", message.EvolveId);
        return Task.FromResult(CheckResult.Pass());
    }

    public Task<CheckResult> CheckTextAsync(
        string evolveId,
        string? remittanceInformation,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("NoOp screening check passed. EvolveId={EvolveId}", evolveId);
        return Task.FromResult(CheckResult.Pass());
    }
}