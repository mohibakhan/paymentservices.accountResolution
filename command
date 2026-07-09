using FluentValidation;
using PaymentServices.RTPSend.Models.Domain;

namespace PaymentServices.RTPSend.Validators;

public class AccountNameValidator : AbstractValidator<AccountName>
{
    public AccountNameValidator()
    {
        // Valid when EITHER a company name is provided, OR both first and last
        // are provided. Mirrors AccountName.ToString() (prefers Company, else
        // "First Last").
        RuleFor(x => x)
            .Must(HaveCompanyOrFullPersonName)
            .WithMessage(
                "Account name must include either a company name, or both first and last name.");
    }

    private static bool HaveCompanyOrFullPersonName(AccountName name)
    {
        var hasCompany = !string.IsNullOrWhiteSpace(name.Company);
        var hasFullPersonName =
            !string.IsNullOrWhiteSpace(name.First) &&
            !string.IsNullOrWhiteSpace(name.Last);

        return hasCompany || hasFullPersonName;
    }
}
