using Evolve.Digital.KeywordScreen.Shared.Services;
using Microsoft.Extensions.Logging;
using PaymentServices.Shared.Messages;

namespace PaymentServices.Transfer.Services;

/// <summary>
/// Keyword screening backed by the Evolve.Digital.KeywordScreen NuGet. Screens
/// the payment's remittance information against the configured keyword list.
/// A positive match (IsPositive) denies the payment.
/// </summary>
public sealed class KeywordScreeningService : IScreeningService
{
    private readonly IKeywordScreenService _keywordScreen;
    private readonly ILogger<KeywordScreeningService> _logger;

    public KeywordScreeningService(
        IKeywordScreenService keywordScreen,
        ILogger<KeywordScreeningService> logger)
    {
        _keywordScreen = keywordScreen;
        _logger = logger;
    }

    public Task<CheckResult> CheckAsync(PaymentMessage message, CancellationToken cancellationToken = default) =>
        CheckTextAsync(message.EvolveId, message.RemittanceInformation, cancellationToken);

    public async Task<CheckResult> CheckTextAsync(
        string evolveId,
        string? remittanceInformation,
        CancellationToken cancellationToken = default)
    {
        var text = remittanceInformation;

        // Nothing to screen — pass. (Remittance info is optional.)
        if (string.IsNullOrWhiteSpace(text))
        {
            _logger.LogInformation(
                "No remittance info to screen. EvolveId={EvolveId}", evolveId);
            return CheckResult.Pass();
        }

        // Refresh the keyword list, then screen.
        await _keywordScreen.ReloadKeywordsAsync();
        var result = _keywordScreen.ScreenText(text);

        if (!result.IsPositive)
        {
            _logger.LogInformation("Screening clear. EvolveId={EvolveId}", evolveId);
            return CheckResult.Pass();
        }

        _logger.LogWarning(
            "Screening MATCH — payment denied. EvolveId={EvolveId} Remittance={Remittance}", evolveId, text);
        var reason = $"Keyword screening matched remittance information: '{text}'";
        return CheckResult.Deny(reason);
    }
}