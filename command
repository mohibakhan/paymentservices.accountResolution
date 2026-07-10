using FluentValidation;
using PaymentServices.RTPSend.Models.Domain;

namespace PaymentServices.RTPSend.Validators;

public class AccountNameValidator : AbstractValidator<AccountName>
{
    public AccountNameValidator()
    {
        RuleFor(x => x)
            .Must(HaveCompanyXorFullPersonName)
            .WithMessage(
                "Account name must include EITHER a company name, OR both first and last name — not both.");
    }

    private static bool HaveCompanyXorFullPersonName(AccountName name)
    {
        var hasCompany = !string.IsNullOrWhiteSpace(name.Company);
        var hasFirst = !string.IsNullOrWhiteSpace(name.First);
        var hasLast = !string.IsNullOrWhiteSpace(name.Last);
        var hasFullPersonName = hasFirst && hasLast;

        // Exactly one of the two forms must be provided.
        // Company path: company present, and NO person-name parts.
        // Person path: first AND last present, and NO company.
        if (hasCompany)
            return !hasFirst && !hasLast;   // company alone, no first/last

        return hasFullPersonName;            // no company → need both first and last
    }
}


[Fact]
public async Task Validate_WhenBothCompanyAndFullName_HasError()
{
    var req = TestDataBuilder.AValidBasicRequest();
    req.SourceAccount!.Name = new AccountName { Company = "Acme Inc", First = "Earnin", Last = "Merchant" };

    var result = await _sut.TestValidateAsync(req);
    result.ShouldHaveValidationErrorFor("SourceAccount.Name");
}
