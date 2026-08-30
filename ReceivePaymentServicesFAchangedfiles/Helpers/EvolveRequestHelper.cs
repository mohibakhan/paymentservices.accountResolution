using System;
using Microsoft.Azure.Cosmos;
using System.Collections.Generic;
using Microsoft.Extensions.Options;
using ReceivePaymentServicesFA.Utility;
using ReceivePaymentServicesFA.Settings;
using ReceivePaymentServicesFA.Interface;
using ReceivePaymentServicesFA.Constants;
using Evolve.Digital.Shared.Models.Payments;
using Evolve.Digital.Core.Utilities.Datetime;
using ReceivePaymentServicesFA.Models.Request;
using ReceivePaymentServicesFA.Models.Response;

namespace ReceivePaymentServicesFA.Helpers;

public class EvolveRequestHelper : IEvolveRequestHelper
{
    private readonly AppSettings _appSettings;
    public EvolveRequestHelper(IOptions<AppSettings> appSettings)
    {
        _appSettings = appSettings.Value;
    }

    public EvolvePaymentRequest CreateReturnRtpDocument(EvolvePaymentRequest createPaymentDocument, TabaPayRequest tabaPayRequest, bool isReturnPayment)
    {
        var evolvePaymentRequest = new EvolvePaymentRequest()
        {
            Type = "push",
            AchOptions = "R",
            PaymentCurrency = "840",
            ValueDate = DateTimeExtensions.ToCosmosDateTime(DateTime.Now),
            TranCode = (isReturnPayment) ? _appSettings.RTP_RECEIVE_RETURN_TRAN_CODE : _appSettings.RTP_RECEIVE_TRAN_CODE,
            CreatedTimeStamp = DateTimeExtensions.ToCosmosDateTime(DateTime.Now),
            DocumentType = (isReturnPayment) ? PaymentRequestConstants.DocumentType : PaymentRequestConstants.DocumentTypeReceive,
            DocumentSubType = PaymentRequestConstants.DocumentSubType,
            //ClientId = headers["x-client-id"].ToString(),
            //MerchantId = headers["x-merchant-id"].ToString(),
            Status = RequestStatus.RECEIVED.ToString(),
            Stage = RequestStage.RTP_API.ToString(),
            TabaPayReferenceId = (isReturnPayment) ? createPaymentDocument.TabaPayReferenceId : null,
            TabaPayTransactionId = (isReturnPayment) ? createPaymentDocument.TabaPayTransactionId : null,
            OrigInstructionId = tabaPayRequest.RemittanceInformation?.OriginalID,
            InstructionId = tabaPayRequest.InstructionId,
            EndToEndId = tabaPayRequest.EndToEndId,
            GluId = (isReturnPayment) ? createPaymentDocument.GluId : null,
            FintechId = (isReturnPayment) ? createPaymentDocument.FintechId : null,
        };

        evolvePaymentRequest.StatusHistory.Add(new StatusHistory()
        {
            Stage = RequestStage.RTP_API.ToString(),
            StatusDate = DateTimeExtensions.ToCosmosDateTime(DateTime.Now),
            Status = RequestStatus.RECEIVED.ToString(),
        });

        // Map basic payment fields to evolve payment request fields
        evolvePaymentRequest.PaymentReference = (isReturnPayment) ? createPaymentDocument.PaymentReference : tabaPayRequest.InstructionId;
        evolvePaymentRequest.SourceAccountId = (isReturnPayment) ? createPaymentDocument.SourceAccountId : null;
        evolvePaymentRequest.Amount = tabaPayRequest.InstructedAmount;
        evolvePaymentRequest.UltimateDebtor = (isReturnPayment) ? createPaymentDocument.UltimateDebtor : null;

        #region sourceAccount
        if (tabaPayRequest.Debtor != null)
        {
            evolvePaymentRequest.SourceAccount = new SourceAccount();
            evolvePaymentRequest.SourceAccount.Name = new AccountName();

            evolvePaymentRequest.SourceAccount.AccountNumber = tabaPayRequest.Debtor.AccountNumber.Trim();
            evolvePaymentRequest.SourceAccount.RoutingNumber = tabaPayRequest.Debtor.RoutingNumber.Trim();
            evolvePaymentRequest.SourceAccount.AccountType = "S";
            evolvePaymentRequest.SourceAccount.DebtorBankMemberID = (isReturnPayment) ? createPaymentDocument.SourceAccount.DebtorBankMemberID : null;
            evolvePaymentRequest.SourceAccount.Name.Company = tabaPayRequest.Debtor.Name;
            evolvePaymentRequest.SourceAccount.Address = new Evolve.Digital.Shared.Models.Payments.Address();
            evolvePaymentRequest.SourceAccount.Address.AddressLines = new List<string>{
                tabaPayRequest.Debtor.Address.Line1
            };
            evolvePaymentRequest.SourceAccount.Address.PostalCode = tabaPayRequest.Debtor.Address.PostalCode;
            evolvePaymentRequest.SourceAccount.Address.City = tabaPayRequest.Debtor.Address.City;
            evolvePaymentRequest.SourceAccount.Address.StateCode = tabaPayRequest.Debtor.Address.State;
            evolvePaymentRequest.SourceAccount.Address.CountryISOCode = tabaPayRequest.Debtor.Address.Country;
        }
        #endregion

        #region destinationAccount
        if (tabaPayRequest.Creditor != null)
        {
            evolvePaymentRequest.DestinationAccount = new DestinationAccount();
            evolvePaymentRequest.DestinationAccount.Name = new AccountName();

            evolvePaymentRequest.DestinationAccount.AccountNumber = tabaPayRequest.Creditor.AccountNumber.Trim();
            evolvePaymentRequest.DestinationAccount.RoutingNumber = tabaPayRequest.Creditor.RoutingNumber.Trim();
            evolvePaymentRequest.DestinationAccount.AccountType = "C";
            //evolvePaymentRequest.DestinationAccount.PhoneNumber = createPaymentDocument.SourceAccount.PhoneNumber;
            //evolvePaymentRequest.DestinationAccount.CreditorAgentTCHMemberID = createPaymentDocument.SourceAccount.CreditorAgentTCHMemberID;
            var name = tabaPayRequest.Creditor.Name.Split();
            try
            {
                evolvePaymentRequest.DestinationAccount.Name.First = name[0];
                evolvePaymentRequest.DestinationAccount.Name.Last = name[1];
                evolvePaymentRequest.DestinationAccount.Name.Company = string.Empty;
            }
            catch (Exception)
            {
                evolvePaymentRequest.DestinationAccount.Name.Last = "";
            }

            evolvePaymentRequest.DestinationAccount.Address = new Evolve.Digital.Shared.Models.Payments.Address();
            evolvePaymentRequest.DestinationAccount.Address.AddressLines = new List<string>{
                tabaPayRequest.Creditor.Address.Line1
            };
            evolvePaymentRequest.DestinationAccount.Address.PostalCode = tabaPayRequest.Creditor.Address.PostalCode;
            evolvePaymentRequest.DestinationAccount.Address.City = tabaPayRequest.Creditor.Address.City;
            evolvePaymentRequest.DestinationAccount.Address.StateCode = tabaPayRequest.Creditor.Address.State;
            evolvePaymentRequest.DestinationAccount.Address.CountryISOCode = tabaPayRequest.Creditor.Address.Country;
        }

        #endregion



        return evolvePaymentRequest;
    }


    public BusinessEvolvePaymentRequest ConvertToBusinessDocument(EvolvePaymentRequest request)
    {
        var statusHistory = new List<BusinessRequestStatusHistory>();

        foreach (var requestStatus in request.StatusHistory)
            statusHistory.Add(new BusinessRequestStatusHistory() { StatusDate = requestStatus.StatusDate, Status = requestStatus.Status });

        return new BusinessEvolvePaymentRequest()
        {
            EvolveId = request.EvolveId,
            Amount = request.Amount,
            CreatedTimeStamp = request.CreatedTimeStamp,
            ModifiedTimeStamp = request.ModifiedTimeStamp,
            TabaPayReferenceId = request.TabaPayReferenceId,
            TabaPayTransactionId = request.TabaPayTransactionId,
            PaymentCurrency = request.PaymentCurrency,
            ClientId = request.ClientId,
            MerchantId = request.MerchantId,
            GluId = request.GluId,
            FintechId = request.FintechId,
            FboAccountName = request.FboAccountName,
            FboAccountNumber = request.FboAccountNumber,
            TaxId = request.TaxId,
            UserIsBusiness = request.UserIsBusiness,
            ValueDate = request.ValueDate,
            PaymentReference = request.PaymentReference,
            SourceAccount = request.SourceAccount,
            DestinationAccount = request.DestinationAccount,
            UltimateDebtor = request.UltimateDebtor,
            StatusHistory = statusHistory
        };
    }

    public RtpCreditRequest CreateRtpCreditRequest(string instructionId, string endToEndId, string amount, string fboAccountNumber, string transactionCode)
    {
        return new RtpCreditRequest()
        {
            AccountId = new AccountId()
            {
                AcctId = fboAccountNumber,
                AcctType = "D"
            },
            TrnInfo = new TrnInfo()
            {
                Amt = amount,
                TrnCodeCode = transactionCode,
                EffDt = DateUtils.GetCentralTimeEffectiveDate(),
                Remarks = new List<string>()
                {
                    instructionId,
                    endToEndId,
                    "RTP Credit"
                }
            }

        };
    }

    /// <summary>
    /// String-stage overload — used for the Transfer pipeline stages
    /// (LIMIT/SCREENING/LEDGER), which are not part of the shared RequestStage enum.
    /// </summary>
    public static List<PatchOperation> GetStatusPatchOperation(string stage, RequestStatus status, object additionalInfo = null)
    {
        string text = DateTime.UtcNow.ToCosmosDateTime();
        return new List<PatchOperation>()
        {
                PatchOperation.Add($"/statusHistory/-",
                new StatusHistory
                {
                    StatusDate = text,
                    Stage = stage,
                    Status = status.ToString(),
                    AddInfo = additionalInfo
                }),
                PatchOperation.Replace($"/stage",stage),
                PatchOperation.Replace($"/status",status.ToString()),
                PatchOperation.Replace($"/modifiedTimeStamp",text)
        };
    }

    /// <summary>
    /// Builds ONE patch for several statusHistory entries (e.g. the
    /// LIMIT/SCREENING/LEDGER stages reported by Transfer): one append per
    /// entry, with the doc-level stage/status set from the LAST entry — the
    /// same shape RTPSend writes from Transfer's outcome message.
    /// </summary>
    public static List<PatchOperation> GetStageHistoryPatchOperations(
        List<(string Stage, RequestStatus Status, object AddInfo)> entries)
    {
        var operations = new List<PatchOperation>();

        if (entries == null || entries.Count == 0)
            return operations;

        string text = DateTime.UtcNow.ToCosmosDateTime();

        foreach (var (stage, status, addInfo) in entries)
        {
            operations.Add(PatchOperation.Add($"/statusHistory/-",
                new StatusHistory
                {
                    StatusDate = text,
                    Stage = stage,
                    Status = status.ToString(),
                    AddInfo = addInfo
                }));
        }

        var last = entries[entries.Count - 1];
        operations.Add(PatchOperation.Replace($"/stage", last.Stage));
        operations.Add(PatchOperation.Replace($"/status", last.Status.ToString()));
        operations.Add(PatchOperation.Replace($"/modifiedTimeStamp", text));

        return operations;
    }

    public static List<PatchOperation> GetStatusPatchOperation(RequestStage stage, RequestStatus status, object additionalInfo = null)
    {
        string text = DateTime.UtcNow.ToCosmosDateTime();
        return new List<PatchOperation>()
        {
                PatchOperation.Add($"/statusHistory/-",
                new StatusHistory
                {
                    StatusDate = text,
                    Stage = stage.ToString(),
                    Status = status.ToString(),
                    AddInfo = additionalInfo
                }),
                PatchOperation.Replace($"/stage",stage.ToString()),
                PatchOperation.Replace($"/status",status.ToString()),
                PatchOperation.Replace($"/modifiedTimeStamp",text)
        };
    }

    public static List<PatchOperation> SetAccountLookupPatchoperation(PartnerLedgerResponse partnerLedgerResponse)
    {
        return new List<PatchOperation>()
        {
                PatchOperation.Replace($"/fboAccount",partnerLedgerResponse.FboAccount.Trim()),
                PatchOperation.Replace($"/fboAccountName",partnerLedgerResponse.FboAccountName.Trim()),
                PatchOperation.Replace($"/fintechId",partnerLedgerResponse.CifNo),
                PatchOperation.Replace($"/taxId",partnerLedgerResponse.TaxId),
                PatchOperation.Replace($"/userIsBusiness",partnerLedgerResponse.IsBusinessUser)
        };
    }

    public static List<PatchOperation> GetJhaTransactionPatchOperation(string trnRcptId)
    {
        return new List<PatchOperation>()
        {
                PatchOperation.Replace($"/trnRcptId",trnRcptId)
        };
    }

    public static List<PatchOperation> GetGluIdUpdatePatchOperation(string gluId, string gludId_s, string gludId_d)
    {
        return new List<PatchOperation>()
        {
                PatchOperation.Replace($"/gluId",gluId),
                PatchOperation.Replace($"/gluId_s",gludId_s),
                PatchOperation.Replace($"/gluId_d",gludId_d)
        };
    }

    public static List<PatchOperation> SetCompanyUpdatePatchOperation(string company, string firstName, string lastName)
    {
        return new List<PatchOperation>()
        {
                PatchOperation.Add($"/destinationAccount/name/company",company),
                PatchOperation.Add($"/destinationAccount/name/first",firstName),
                PatchOperation.Add($"/destinationAccount/name/last",lastName)
        };
    }

    public DepositHistoryRequest CreateDepoistHistoryRequest(RtpCreditRequest rtpCreditRequest, string memoPostInc)
    {
        var request = new DepositHistoryRequest()
        {
            InAcctId = new InAcctId
            {
                AcctId = rtpCreditRequest.AccountId.AcctId,
                AcctType = rtpCreditRequest.AccountId.AcctType
            },
            ChkNumEnd = null,
            ChkNumStart = null,
            StartDt = rtpCreditRequest.TrnInfo.EffDt,
            EndDt = rtpCreditRequest.TrnInfo.EffDt,
            HighAmt = rtpCreditRequest.TrnInfo.Amt,
            LowAmt = rtpCreditRequest.TrnInfo.Amt,
            TrnType = null,
            MemoPostInc = memoPostInc,
            MaxRtnRec = "10",
            XferKey = null,
            TrnRcptId = null
        };
        return request;
    }
}