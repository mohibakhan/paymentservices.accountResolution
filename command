[Fact]
public async Task Validate_WhenSoftDescriptorHasValidAddress_NoError()
{
    var req = TestDataBuilder.AValidBasicRequest();
    req.SoftDescriptor = new SoftDescriptor
    {
        Name = "Test Merchant",
        Address = new Address
        {
            AddressLines = new List<string> { "200 Main Street" },
            City = "Omaha",
            County = "055",
            StateCode = "NE",
            PostalCode = "68102",
            CountryISOCode = "840"
        }
    };

    var result = await _sut.TestValidateAsync(req);
    result.ShouldNotHaveValidationErrorFor("SoftDescriptor.Address");
}
