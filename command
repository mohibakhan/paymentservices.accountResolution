PaymentServices.RTPSend.UnitTests.Validators.BasicPaymentRequestValidatorTests.Validate_WhenSoftDescriptorHasValidAddress_NoError
   Source: BasicPaymentRequestValidatorTests.cs line 144
   Duration: 6 ms

  Message: 
FluentValidation.AsyncValidatorInvokedSynchronouslyException : BasicPaymentRequestValidator contains asynchronous rules - please use the asynchronous test methods instead.

  Stack Trace: 
ValidationTestExtension.TestValidate[T](IValidator`1 validator, ValidationContext`1 context)
ValidationTestExtension.TestValidate[T](IValidator`1 validator, T objectToTest, Action`1 options)
BasicPaymentRequestValidatorTests.Validate_WhenSoftDescriptorHasValidAddress_NoError() line 160
MethodBaseInvoker.InterpretedInvoke_Method(Object obj, IntPtr* args)
MethodBaseInvoker.InvokeWithNoArgs(Object obj, BindingFlags invokeAttr)
