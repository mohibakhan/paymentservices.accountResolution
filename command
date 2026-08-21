// TabaPay expects ISO 3166-1 numeric (e.g. 840 for US). Alpha-3 ("USA") is
// rejected downstream with EC 3C5E1961 on address.country — fail at intake
// instead, before the ledger is debited.
RuleFor(x => x.CountryISOCode)
    .Cascade(CascadeMode.Stop)
    .NotNull()
    .NotEmpty()
    .Matches(@"^\d{3}$")
    .WithMessage("CountryISOCode must be a 3-digit ISO 3166-1 numeric code (e.g. 840 for US)");
