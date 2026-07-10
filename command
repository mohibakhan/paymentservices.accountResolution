.Custom((x, context) =>
{
    if (!decimal.TryParse(x, System.Globalization.NumberStyles.Number,
                          System.Globalization.CultureInfo.InvariantCulture, out var value)
        || value <= 0)
    {
        context.AddFailure($"{x} is not a valid amount; must be a positive number");
    }
});
