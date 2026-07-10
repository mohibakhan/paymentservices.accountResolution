[Fact]
public void Validate_WhenSoftDescriptorHasValidAddress_NoError()
{
    var req = TestDataBuilder.AValidBasicRequest();
    req.SoftDescriptor = new SoftDescriptor
    {
        Name = "Test Merchant",
        Address = new Address
        {
            AddressLines = new List<string> { "200 Main Street" },
            City = "Omaha",
            County = "055",           // 3-char county code
            StateCode = "NE",         // real US state
            PostalCode = "68102",     // valid US 5-digit
            CountryISOCode = "840"    // US, ISO numeric
        }
    };
    _sut.TestValidate(req)
        .ShouldNotHaveValidationErrorFor("SoftDescriptor.Address");
}
