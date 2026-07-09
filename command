// TransferCompleted means screening, limits, and the ledger debit all passed
// in Transfer. Record that on the doc (authoritative — Transfer owns these
// stages) before calling TabaPay, so the history reflects it even though
// TabaPay runs immediately after.
var screeningPatches = EvolvePaymentRequestHelper.GetStatusPatchOperation(
    RequestStage.SCREENING,
    RequestStatus.COMPLETED,
    additionalInfo: new { Message = "Screening and limits passed" });

payment = await _paymentCosmosDB.PatchItemAsync(payment, screeningPatches) ?? payment;

_logger.LogInformation(
    "Screening and limits passed for {EvolveId}; calling TabaPay.", outcome.EvolveId);
