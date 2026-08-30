using Evolve.Digital.LimitsService.Shared.Internal;
using Evolve.Digital.LimitsService.Shared.Internal.Models;
using Microsoft.Extensions.Logging;
using PaymentServices.Shared.Messages;

namespace PaymentServices.Transfer.Services;

/// <summary>
/// Limit check backed by the Evolve.Digital.LimitsService NuGet. Evaluates all
/// limits in the requested category ("Send" for outbound transfers,
/// "Receive" for inbound RTP credits) for the FBO account against the payment
/// amount, updating usage on approval.
/// </summary>
public sealed class EvolveLimitService : ILimitService
{
    private readonly ILimitsInternalClient _limitsClient;
    private readonly ILogger<EvolveLimitService> _logger;

    public EvolveLimitService(
        ILimitsInternalClient limitsClient,
        ILogger<EvolveLimitService> logger)
    {
        _limitsClient = limitsClient;
        _logger = logger;
    }

    public Task<CheckResult> CheckAsync(
        PaymentMessage message,
        string category = LimitCategories.Send,
        CancellationToken cancellationToken = default) =>
        CheckAsync(message.EvolveId, message.FboAccount ?? string.Empty, message.Amount, category, cancellationToken);

    public async Task<CheckResult> CheckAsync(
        string evolveId,
        string fboAccount,
        string amount_s,
        string category,
        CancellationToken cancellationToken = default)
    {
        if (!decimal.TryParse(amount_s, out var amount))
        {
            _logger.LogError("Invalid amount '{Amount}' for limit check. EvolveId={EvolveId}",
                amount_s, evolveId);
            return CheckResult.Deny($"Amount '{amount_s}' is not a valid decimal");
        }

        var partitionKey = fboAccount ?? string.Empty;
        if (string.IsNullOrWhiteSpace(partitionKey))
        {
            _logger.LogError("No FBO account for limit check. EvolveId={EvolveId}", evolveId);
            return CheckResult.Deny("No FBO account available for limit evaluation");
        }

        var request = new EvaluateCategoryRequest(
            PartitionKey: partitionKey,
            Category: category,
            Amount: amount,
            UpdateUsage: true);

        var response = await _limitsClient.EvaluateCategoryLimitsAsync(request);

        if (response.Approved)
        {
            _logger.LogInformation(
                "Limit check approved. EvolveId={EvolveId} Pk={Pk} Category={Category} Amount={Amount}",
                evolveId, partitionKey, category, amount);
            return CheckResult.Pass();
        }

        var reason = $"Limit denied ({response.FailedLimit?.LimitType}): {response.Message}";
        _logger.LogWarning(
            "Limit check DENIED. EvolveId={EvolveId} Category={Category} FailedLimit={LimitType} Message={Message}",
            evolveId, category, response.FailedLimit?.LimitType, response.Message);
        return CheckResult.Deny(reason);
    }
}