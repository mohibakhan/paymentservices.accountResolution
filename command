RuleFor(x => x.CountryISOCode)
    .Cascade(CascadeMode.Stop)
    .NotNull()
    .NotEmpty()
    .WithMessage("country code is required")
    .Length(3).WithMessage("Country code must be exactly 3 characters long")
    .MustAsync(BeAValidIso3166NumericCode)
    .WithMessage("Invalid ISO 3166-1 numeric country code");
