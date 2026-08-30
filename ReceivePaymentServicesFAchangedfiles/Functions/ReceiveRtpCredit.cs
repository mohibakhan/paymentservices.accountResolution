using System;
using System.Net;
using System.Linq;
using Newtonsoft.Json;
using System.Net.Http;
using FluentValidation;
using System.Threading.Tasks;
using Microsoft.Azure.Cosmos;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using System.Collections.Generic;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.Functions.Worker;
using Evolve.Digital.Core.Utilities.Http;
using ReceivePaymentServicesFA.Constants;
using ReceivePaymentServicesFA.Exceptions;
using ReceivePaymentServicesFA.Interface;
using Evolve.Digital.Shared.Models.Payments;
using ReceivePaymentServicesFA.Models.Request;
using ReceivePaymentServicesFA.Models.Response;
using ReceivePaymentServicesFA.Services.Facade;
using ReceivePaymentServicesFA.Interface.CosmosDataAdapter;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;
using ServiceErrorResponse = ReceivePaymentServicesFA.Models.ServiceErrorResponse;

namespace ReceivePaymentServicesFA.Functions;

public class ReceiveRtpCredit
{
    private readonly IPaymentCosmosDBService _paymentCosmosDBService;
    private readonly IEvolveRequestHelper _evolveRequestHelper;
    private readonly IValidator<TabaPayRequest> _validator;
    private readonly ILogger<ReceiveRtpCredit> log;
    private readonly IPreRtpChecksFacade _facade;

    /// <summary>
    /// Constructor method for ReceiveCredit
    /// </summary>
    /// <param name="jhaService"></param>
    /// <param name="prefundLedgerService"></param>
    /// <param name="paymentCosmosDBService"></param>
    /// <param name="httpContextAccessor"></param>
    /// <param name="telemetryClient"></param>
    /// <param name="partnerLedgerService"></param>
    public ReceiveRtpCredit(
        IPaymentCosmosDBService paymentCosmosDBService,
        IEvolveRequestHelper evolveRequestHelper,
        IValidator<TabaPayRequest> validator,
        IPreRtpChecksFacade facade,
        ILogger<ReceiveRtpCredit> logger
        )
    {
        _paymentCosmosDBService = paymentCosmosDBService;
        _evolveRequestHelper = evolveRequestHelper;
        _validator = validator;
        _facade = facade;
        log = logger;
    }

    /// <summary>
    /// Receives request from TabaPay, validates it via RTP and posts to JHA
    /// </summary>
    /// <param name="req"></param>
    /// <param name="log"></param>
    /// <returns></returns>
    [Function("ReceiveRtpCredit")]
    [OpenApiOperation(operationId: "ReceiveRtpCredit", tags: new[] { "ReceiveRtpCredit" })]
    [OpenApiRequestBody(contentType: "application/json", bodyType: typeof(TabaPayRequest), Description = "TabaPayRequest", Required = true)]
    [OpenApiResponseWithBody(statusCode: HttpStatusCode.OK, contentType: "application/json", bodyType: typeof(TabaPayResponse), Description = "The OK response")]
    [OpenApiResponseWithBody(statusCode: HttpStatusCode.BadRequest, contentType: "application/json", bodyType: typeof(TabaPayResponse), Description = "Bad Request")]
    [OpenApiResponseWithBody(statusCode: HttpStatusCode.InternalServerError, contentType: "application/json", bodyType: typeof(TabaPayResponse), Description = "Internal Server Error")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req)
    {
        try
        {

            // Get request
            var tabaPayRequest = await req.GetJsonBodyAsync<TabaPayRequest>();

            log.LogInformation($"Request body: {JsonConvert.SerializeObject(tabaPayRequest)}");

            // Get headers
            var headers = req.Headers;

            if (tabaPayRequest == null)
            {
                var tabaPayResponse = new TabaPayResponse()
                {
                    Status = "ERROR",
                    StatusReasonDescription = "Invalid request."
                };
                log.LogError($"Bad request. Response {JsonConvert.SerializeObject(tabaPayResponse)}");
                return await ActionResultResponseHelper.CreateBadRequestAsync(req.HttpContext, tabaPayResponse);
            }

            var fluentValidationResult = await _validator.ValidateAsync(tabaPayRequest);
            if (!fluentValidationResult.IsValid)
            {
                var serviceErrorResponse = new ServiceErrorResponse
                {
                    Error = "Invalid request",
                    Message = "Please correct the following errors in the request.",
                    AddInfo = fluentValidationResult.Errors.Select(e => new
                    {
                        e.PropertyName,
                        e.ErrorMessage
                    })
                };
                log.LogError($"Bad request.  Failed fluent validation. Response {JsonConvert.SerializeObject(serviceErrorResponse)}");
                return await ActionResultResponseHelper.CreateBadRequestAsync(req.HttpContext, serviceErrorResponse);
            }

            var patchOperation_Status = new List<PatchOperation>();
            bool isReturnPayment = false;
            EvolvePaymentRequest createPaymentDocument = new();

            // Check for duplicated instruction id
            var isDuplicate = await _paymentCosmosDBService.FindIfDuplicateAsync(tabaPayRequest.InstructionId);
            if (isDuplicate)
            {
                var tabaPayResponse = new TabaPayResponse()
                {
                    Status = "ERROR",
                    StatusReasonDescription = $"A unique instruction Id is required.  Instruction Id {tabaPayRequest.InstructionId} already exists."
                };
                log.LogError($"Duplicate instruction id {tabaPayRequest.InstructionId} passed. Response {JsonConvert.SerializeObject(tabaPayResponse)}");
                return await ActionResultResponseHelper.CreateBadRequestAsync(req.HttpContext, tabaPayResponse);
            }

            if (tabaPayRequest.RemittanceInformation != null)
            {
                isReturnPayment = true;

                if (tabaPayRequest.RemittanceInformation.OriginalID == null ||
                tabaPayRequest.RemittanceInformation.OriginalID == string.Empty)
                {
                    var serviceErrorResponse = new ServiceErrorResponse
                    {
                        Error = "Invalid original Id",
                        Message = "Please pass a valid original id in the request."
                    };
                    log.LogWarning($"ServiceErrorResponse: {JsonConvert.SerializeObject(serviceErrorResponse)}");
                    return await ActionResultResponseHelper.CreateBadRequestAsync(req.HttpContext, serviceErrorResponse);
                }

                // Additional checks to validate return payment
                #region ADDITIONAL CHECKS

                // Find CreatePaymentDocument -- Return payment
                createPaymentDocument = (await _paymentCosmosDBService.FindAllItemsAsync(
                    tabaPayRequest.RemittanceInformation.OriginalID,
                    PaymentRequestConstants.SendDocumentType,
                    PaymentRequestConstants.SendDocumentSubType)).FirstOrDefault();

                // Handle if cosmos document not found
                if (createPaymentDocument == null)
                {
                    log.LogError("RTPReceive Error from TabaPay.  Could not find transaction.");
                    return await ActionResultResponseHelper.CreateNotFoundAsync(req.HttpContext, new ServiceErrorResponse
                    {
                        Error = "Transaction not found",
                        Message = "Requested transaction could not be found."
                    });
                }

                // Confirm whether returned amount is less or equal to original transaction
                var totalReturnedamount = (await _paymentCosmosDBService.FindReturnedAmountAsync(createPaymentDocument.PaymentReference,
                    PaymentRequestConstants.DocumentType, PaymentRequestConstants.DocumentSubType)).FirstOrDefault().ReturnedAmount;

                var currentTotalReturnedAmount = totalReturnedamount + Convert.ToDouble(tabaPayRequest.InstructedAmount);

                if ((totalReturnedamount == Convert.ToDouble(createPaymentDocument.Amount)) ||
                    currentTotalReturnedAmount > Convert.ToDouble(createPaymentDocument.Amount))
                {
                    log.LogError("RTPReceive Error from TabaPay.  Return amount is greater than transaction amount or return has been previously processed.");
                    return await ActionResultResponseHelper.CreateBadRequestAsync(req.HttpContext, new ServiceErrorResponse
                    {
                        Error = "Transaction could not be processed",
                        Message = "Return amount is greater than transaction amount."
                    });
                }

                #endregion

                log.LogInformation("Transaction of type RTP Return.");
            }

            if (!isReturnPayment)
                log.LogInformation("Transaction of type RTP Receive.");

            // Create return cosmos document
            var returnPaymentDocumentRequest = _evolveRequestHelper.CreateReturnRtpDocument(createPaymentDocument, tabaPayRequest, isReturnPayment);

            // Store in cosmos
            var cosmosDocument = await _paymentCosmosDBService.CreateItemAsync(returnPaymentDocumentRequest);

            // Perform pre - transaction checks.  Call to partner ledger and prefund ledger
            var performPreRtpSendChecks = await _facade.PerformPreRtpChecks(cosmosDocument, isReturnPayment);

            return await ActionResultResponseHelper.CreateOkAsync(req.HttpContext, new TabaPayResponse()
            {
                Status = "ACCEPTED",
            });
        }
        catch(CounterPartyException ex)
        {
            log.LogError(ex, "Receive Payment Services CounterPartyException: {Message}, {Stack}, {Inner_Exception}", ex.Message, ex.StackTrace, ex.InnerException);
            return await ActionResultResponseHelper.CreateOkAsync(req.HttpContext, new TabaPayResponse()
            {
                Status = PaymentRequestConstants.TabaPayRejected,
                StatusReason = "AG03"
            });
        }
        catch (PartnerLedgerException ex)
        {
            log.LogError(ex, "Receive Payment Services PartnerLedgerException: {Message}, {Stack}, {Inner_Exception}", ex.Message, ex.StackTrace, ex.InnerException);

            string statusReason = "";
            string statusReasonDescription = null;

            // Determine the status reason based on the exception message
            switch (ex.Message)
            {
                case "Invalid V Account":
                    statusReason = "AC03";
                    statusReasonDescription = ex.Message;
                    break;
                case "CLOSED":
                    statusReason = "AC04";
                    break;
                case "BLOCKED":
                    statusReason = "AC06";
                    break;
                default:
                    statusReason = "ERROR";
                    statusReasonDescription = "An internal error occurred";
                    break;
            }

            // Create and return appropriate response
            var response = new TabaPayResponse()
            {
                Status = PaymentRequestConstants.TabaPayRejected,
                StatusReason = statusReason,
                StatusReasonDescription = statusReasonDescription
            };

            if (statusReason == "ERROR")
                return await ActionResultResponseHelper.CreateInternalServerErrorAsync(req.HttpContext, response);

            return await ActionResultResponseHelper.CreateOkAsync(req.HttpContext, response);

        }
        catch (TransferException ex)
        {
            log.LogError(ex, "Receive Payment Services TransferException: {Message}, {Stack}, {Inner_Exception}", ex.Message, ex.StackTrace, ex.InnerException);
            if (ex.IsBusinessRejection)
            {
                // Limit or screening denied the payment — terminal business rejection.
                return await ActionResultResponseHelper.CreateOkAsync(req.HttpContext, new TabaPayResponse()
                {
                    Status = PaymentRequestConstants.TabaPayRejected,
                    StatusReason = "AC06",
                    StatusReasonDescription = string.IsNullOrWhiteSpace(ex.FailedStage)
                        ? "Transfer checks failed"
                        : $"{ex.FailedStage} check failed"
                });
            }
            return await ActionResultResponseHelper.CreateInternalServerErrorAsync(req.HttpContext, new TabaPayResponse()
            {
                Status = PaymentRequestConstants.TabaPayError,
                StatusReason = "Internal error",
                StatusReasonDescription = "An internal error occurred"
            });
        }
        catch (PrefundLedgerException ex)
        {
            log.LogError(ex, "Receive Payment Services PrefundLedgerException: {Message}, {Stack}, {Inner_Exception}", ex.Message, ex.StackTrace, ex.InnerException);
            if (ex.Message.Contains("Fraud/Sanctions Failed"))
            {
                return await ActionResultResponseHelper.CreateOkAsync(req.HttpContext, new TabaPayResponse()
                {
                    Status = PaymentRequestConstants.TabaPayRejected,
                    StatusReason = "AC06",
                    StatusReasonDescription = "Fraud/Sanctions check failed"
                });
            }
            return await ActionResultResponseHelper.CreateInternalServerErrorAsync(req.HttpContext, new TabaPayResponse()
            {
                Status = PaymentRequestConstants.TabaPayError,
                StatusReason = "Internal error",
                StatusReasonDescription = "An internal error occurred"
            });
        }
        catch (JsonException ex)
        {
            log.LogError(ex, "Recive Payment Services Json Deserialization Error: {Message}, {Stack}", ex.Message, ex.StackTrace);
            return await ActionResultResponseHelper.CreateInternalServerErrorAsync(req.HttpContext, new TabaPayResponse()
            {
                Status = PaymentRequestConstants.TabaPayError,
                StatusReason = "Internal error",
                StatusReasonDescription = "An internal error occurred"
            });
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Recive Payment Services function Error: {Message}, {Stack}", ex.Message, ex.StackTrace);
            return await ActionResultResponseHelper.CreateInternalServerErrorAsync(req.HttpContext, new TabaPayResponse()
            {
                Status = PaymentRequestConstants.TabaPayError,
                StatusReason = "Internal error",
                StatusReasonDescription = "An internal error occurred"
            });
        }
    }
}

public static class GetIPHelper
{
    public static async Task<string> GetIP()
    {
        var http = new HttpClient()
        {
            BaseAddress = new Uri("https://api.my-ip.io/ip")
        };

        return await http.GetStringAsync("");
    }
}