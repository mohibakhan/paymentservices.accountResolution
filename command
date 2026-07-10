// SoftDescriptor block (entire block is optional per TabaPay)
When(s => s.SoftDescriptor != null, () =>
{
    RuleFor(s => s.SoftDescriptor!.Name)
        .Cascade(CascadeMode.Stop)
        .NotNull()
        .NotEmpty()
        .WithMessage("Soft Descriptor 'Name' is required when SoftDescriptor is supplied");

    // Address is REQUIRED when SoftDescriptor is supplied (TabaPay: address required).
    RuleFor(s => s.SoftDescriptor!.Address)
        .NotNull()
        .WithMessage("Soft Descriptor 'Address' is required when SoftDescriptor is supplied");

    When(s => s.SoftDescriptor!.Address != null, () =>
    {
        RuleFor(s => s.SoftDescriptor!.Address!)
            .SetValidator(new SoftDescriptorAddressValidator());
    });

    // Phone is optional, but if supplied, Number must be present
    When(s => s.SoftDescriptor!.Phone != null, () =>
    {
        RuleFor(s => s.SoftDescriptor!.Phone!.Number)
            .Cascade(CascadeMode.Stop)
            .NotEmpty()
            .NotNull()
            .WithMessage("Soft Descriptor 'Phone.Number' is required when Phone is supplied");
    });
});


using System.Text.RegularExpressions;
using FluentValidation;
using PaymentServices.RTPSend.Helpers.ISO3166;
using PaymentServices.RTPSend.Models.Domain;

namespace PaymentServices.RTPSend.Validators;

public class SoftDescriptorAddressValidator : AbstractValidator<Address>
{
    private const string CountryUsNumeric = "840";
    private const string CountryCanadaNumeric = "124";

    // 50 states + DC.
    private static readonly HashSet<string> UsStateCodes = new(StringComparer.OrdinalIgnoreCase)
    {
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
        "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
        "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
        "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY",
        "DC"
    };

    // US: 5 digits, 9 digits, or ZIP+4 with hyphen.
    private static readonly Regex UsZip = new(@"^\d{5}(-?\d{4})?$", RegexOptions.Compiled);

    // Canada: A1A 1A1 (space optional, case-insensitive).
    private static readonly Regex CaPostal =
        new(@"^[A-Za-z]\d[A-Za-z]\s?\d[A-Za-z]\d$", RegexOptions.Compiled);

    public SoftDescriptorAddressValidator()
    {
        RuleFor(x => x.AddressLines)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .WithMessage("Address is required");

        RuleFor(x => x.City)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .WithMessage("City is required");

        RuleFor(x => x.County)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .WithMessage("County is required")
            .Length(3).WithMessage("County code must be exactly 3 characters long");

        RuleFor(x => x.StateCode)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .WithMessage("state code is required")
            .Length(2).WithMessage("State code must be exactly 2 characters long")
            // For US addresses, the 2-char state must be a real US state / DC code.
            // Non-US addresses only get the length check above.
            .Must((address, stateCode) => IsStateCodeValid(address.CountryISOCode, stateCode))
            .WithMessage("State code must be a valid 2-letter US state or DC code (e.g. NE, CA, TX).");

        RuleFor(x => x.PostalCode)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .WithMessage("postal code is required")
            // Country-conditional format: US (840) 5/9-digit, CA (124) A1A 1A1,
            // other countries not format-checked.
            .Must((address, postalCode) => IsPostalCodeValid(address.CountryISOCode, postalCode))
            .WithMessage(BuildZipMessage);

        RuleFor(x => x.CountryISOCode)
            .Cascade(CascadeMode.Stop)
            .NotNull()
            .NotEmpty()
            .WithMessage("country code is required")
            .Length(3).WithMessage("Country code must be exactly 3 characters long")
            .MustAsync(BeAValidIso3166NumericCode)
            .WithMessage("Invalid ISO 3166-1 numeric country code");
    }

    private static bool IsStateCodeValid(string? countryIsoCode, string? stateCode)
    {
        // Only enforce the real-US-state list for US addresses. Other countries
        // pass with just the length check applied earlier in the chain.
        if (countryIsoCode?.Trim() != CountryUsNumeric)
            return true;

        return stateCode is not null && UsStateCodes.Contains(stateCode.Trim());
    }

    private static bool IsPostalCodeValid(string? countryIsoCode, string? postalCode)
    {
        var country = countryIsoCode?.Trim();
        var zip = postalCode?.Trim() ?? string.Empty;

        return country switch
        {
            CountryUsNumeric => UsZip.IsMatch(zip),
            CountryCanadaNumeric => CaPostal.IsMatch(zip),
            _ => true // other countries not format-checked
        };
    }

    private static string BuildZipMessage(Address address)
    {
        var country = address.CountryISOCode?.Trim();
        return country switch
        {
            CountryUsNumeric => "US postalCode (zip) must be 5 digits or 9 digits (e.g. 12345 or 12345-6789).",
            CountryCanadaNumeric => "Canadian postalCode must be in A1A 1A1 format.",
            _ => "postalCode is invalid for the specified country."
        };
    }

    private static async Task<bool> BeAValidIso3166NumericCode(string? code, CancellationToken token)
    {
        if (string.IsNullOrEmpty(code)) return false;
        var list = await CountryCodeHelper.GetListAsync();
        return list.Any(c => c.Code == code);
    }
}
