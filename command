using System.Globalization;

// in ConvertEvolveToTabaPayRequest:
Amount = FormatTabaPayAmount(evolve.Amount),

/// <summary>
/// TabaPay requires the amount with exactly 2 decimal places — it rejects "0.9"
/// with {"SC":400,"EC":"3C5E1221","EM":"amount"} even though the value is valid.
/// Normalize here so callers can send "0.9", "1", or "1.50" and all work.
/// If the amount can't be parsed we pass it through unchanged and let TabaPay
/// reject it (the request validator should have caught it first).
/// </summary>
private static string FormatTabaPayAmount(string amount) =>
    decimal.TryParse(amount, NumberStyles.Number, CultureInfo.InvariantCulture, out var value)
        ? value.ToString("F2", CultureInfo.InvariantCulture)
        : amount;
