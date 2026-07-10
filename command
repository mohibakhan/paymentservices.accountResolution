[Theory]
[InlineData("0.01")]
[InlineData("100.00")]
[InlineData("99999999.99")]
public void Validate_WhenAmountIsValid_NoError(string amount)
{
    var req = TestDataBuilder.AValidBasicRequest();
    req.Amount = amount;
    _sut.TestValidate(req)
        .ShouldNotHaveValidationErrorFor(r => r.Amount);
}

[Theory]
[InlineData("0")]
[InlineData("-1")]
[InlineData("-0.01")]
[InlineData("abc")]
[InlineData("")]
public void Validate_WhenAmountIsInvalid_HasError(string amount)
{
    var req = TestDataBuilder.AValidBasicRequest();
    req.Amount = amount;
    _sut.TestValidate(req)
        .ShouldHaveValidationErrorFor(r => r.Amount);
}
