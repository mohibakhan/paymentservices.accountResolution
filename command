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
