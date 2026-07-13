Microsoft.CSharp.RuntimeBinder.RuntimeBinderException
  HResult=0x80131500
  Message='System.Text.Json.JsonElement' does not contain a definition for 'id'
  Source=System.Linq.Expressions
  StackTrace:
   at System.Dynamic.UpdateDelegates.UpdateAndExecute1[T0,TRet](CallSite site, T0 arg0)
   at Evolve.Digital.LedgerService.Shared.Services.LedgerService.<UpdateLedgerItemStatus>d__19.MoveNext()
   at Evolve.Digital.LedgerService.Shared.Internal.LedgerInternalClient.<UpdateEntryStatusAsync>d__11.MoveNext()
   at PaymentServices.Transfer.Functions.TptchStatusFunction.<RunAsync>d__4.MoveNext() in C:\Users\mxk221019\MyRepos\PaymentServices.Transfer\src\Functions\TptchStatusFunction.cs:line 83
 
  This exception was originally thrown at this call stack:
    [External Code]
    PaymentServices.Transfer.Functions.TptchStatusFunction.RunAsync(Microsoft.Azure.Functions.Worker.Http.HttpRequestData, System.Threading.CancellationToken) in TptchStatusFunction.cs
 
this is the error now
