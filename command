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

        // Optional on the source account — unlike destination, where TabaPay
        // requires it. But when supplied it must be well-formed, so a bad
        // country code is caught here rather than downstream.
        RuleFor(x => x.Address!)
            .SetValidator(new AddressValidator())
            .When(x => x.Address is not null);
    }
}
