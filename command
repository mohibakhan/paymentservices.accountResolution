using FluentValidation;
using AccountTypeEnum = PaymentServices.RTPSend.Models.Domain.AccountType;
using PaymentServices.RTPSend.Models.Domain;

namespace PaymentServices.RTPSend.Validators;

public class DestinationAccountValidator : AbstractValidator<DestinationAccount>
{
    public DestinationAccountValidator()
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
            .WithMessage("Destination Account name is required")
            .SetValidator(new AccountNameValidator());

        RuleFor(x => x.RoutingNumber)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .Custom((x, context) =>
            {
                if (!ulong.TryParse(x, out _))
                    context.AddFailure($"{x} is not a valid Routing number");
            });

        RuleFor(x => x.AccountType)
            .NotEmpty()
            .NotNull()
            .IsEnumName(typeof(AccountTypeEnum))
            .WithMessage("Invalid Destination Account type is required and can be one of the following values: S, C, A, B, L");

        // TabaPay requires the destination address (line1/city/state/zip).
        // Required (not null) + field-level validation via AddressValidator.
        RuleFor(x => x.Address)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .WithMessage("Destination Account address is required")
            .SetValidator(new AddressValidator()!);
    }
}


using System.Text.RegularExpressions;
using FluentValidation;
using PaymentServices.RTPSend.Models.Domain;

namespace PaymentServices.RTPSend.Validators;

/// <summary>
/// Validates the fields TabaPay requires on a destination address.
/// Incoming Address uses addressLines[] + stateCode + countryISOCode; these map
/// to TabaPay's line1 / state / country via the (TabapayAddress) operator.
///
/// Rules:
///   - addressLines[0] (TabaPay line1) required
///   - city required
///   - stateCode required + must be a real 2-letter US state/DC code
///   - postalCode (zip) validated by country:
///       * 840 (US): 5 digits or 9 digits (optionally 5+4 with a hyphen)
///       * 124 (CA): A1A 1A1 format (case-insensitive, space optional)
///       * other countries: not checked
/// </summary>
public class AddressValidator : AbstractValidator<Address>
{
    private const string CountryUs = "840";
    private const string CountryCanada = "124";

    // 50 states + DC only.
    private static readonly HashSet<string> UsStateCodes = new(StringComparer.OrdinalIgnoreCase)
    {
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
        "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
        "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
        "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY",
        "DC"
    };

    // US: exactly 5 digits, or 9 digits, or ZIP+4 with hyphen (12345-6789).
    private static readonly Regex UsZip = new(@"^\d{5}(-?\d{4})?$", RegexOptions.Compiled);

    // Canada: A1A 1A1 (letter-digit-letter [space] digit-letter-digit).
    private static readonly Regex CaPostal =
        new(@"^[A-Za-z]\d[A-Za-z]\s?\d[A-Za-z]\d$", RegexOptions.Compiled);

    public AddressValidator()
    {
        // line1 == addressLines[0]; TabaPay requires it.
        RuleFor(x => x.AddressLines)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .Must(lines => lines is { Count: > 0 } && !string.IsNullOrWhiteSpace(lines[0]))
            .WithMessage("Address line1 is required (addressLines[0]).");

        RuleFor(x => x.City)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .WithMessage("Address city is required.");

        RuleFor(x => x.StateCode)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .WithMessage("Address stateCode is required.")
            .Must(code => code is not null && UsStateCodes.Contains(code.Trim()))
            .WithMessage("Address stateCode must be a valid 2-letter US state or DC code (e.g. NE, CA, TX).");

        // Zip is validated by country. Only US (840) and CA (124) are checked;
        // other countries are not checked (any value, including empty, passes).
        RuleFor(x => x.PostalCode)
            .Must((address, postalCode) => IsPostalCodeValid(address.CountryISOCode, postalCode))
            .WithMessage(BuildZipMessage);
    }

    private static bool IsPostalCodeValid(string? countryIsoCode, string? postalCode)
    {
        var country = countryIsoCode?.Trim();
        var zip = postalCode?.Trim() ?? string.Empty;

        return country switch
        {
            CountryUs => UsZip.IsMatch(zip),
            CountryCanada => CaPostal.IsMatch(zip),
            _ => true // other countries not checked
        };
    }

    private static string BuildZipMessage(Address address)
    {
        var country = address.CountryISOCode?.Trim();
        return country switch
        {
            CountryUs => "US postalCode (zip) must be 5 digits or 9 digits (e.g. 12345 or 12345-6789).",
            CountryCanada => "Canadian postalCode must be in A1A 1A1 format.",
            _ => "postalCode is invalid for the specified country."
        };
    }
}
