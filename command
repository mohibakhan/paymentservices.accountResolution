RuleFor(x => x.CountryISOCode)
    .Cascade(CascadeMode.Stop)
    .NotNull()
    .NotEmpty()
    .WithMessage("country code is required")
    .Length(3).WithMessage("Country code must be exactly 3 characters long")
    .MustAsync(BeAValidIso3166NumericCode)
    .WithMessage("Invalid ISO 3166-1 numeric country code");

using FluentValidation;
using AccountTypeEnum = PaymentServices.RTPSend.Models.Domain.AccountType;
using PaymentServices.RTPSend.Models.Domain;

namespace PaymentServices.RTPSend.Validators;

public class SourceAccountValidator : AbstractValidator<SourceAccount>
{
    public SourceAccountValidator()
    {
        RuleFor(x => x.AccountNumber)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .Custom((x, context) =>
            {
                if (!ulong.TryParse(x, out _))
                    context.AddFailure($"{x} is not a valid account number");
            });

        RuleFor(x => x.Name)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .WithMessage("Source Account name is required")
            .SetValidator(new AccountNameValidator());

        RuleFor(x => x.RoutingNumber)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .Matches(@"^\d{8,9}$")
            .WithMessage("Routing number must be 8 or 9 digits");

        RuleFor(x => x.AccountType)
            .NotEmpty()
            .NotNull()
            .IsEnumName(typeof(AccountTypeEnum))
            .WithMessage("Invalid Source AccountType is required and can be one of the following values: S, C, A, B, L");
    }
}
