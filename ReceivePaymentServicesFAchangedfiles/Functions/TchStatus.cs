using System;
using System.Net;
using System.Linq;
using Newtonsoft.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ReceivePaymentServicesFA.Settings;
using Microsoft.Azure.Functions.Worker;
using ReceivePaymentServicesFA.Helpers;
using Evolve.Digital.Core.Utilities.Http;
using ReceivePaymentServicesFA.Constants;
using ReceivePaymentServicesFA.Interface;
using Evolve.Digital.Shared.Models.Payments;
using ReceivePaymentServicesFA.Models.Request;
using ReceivePaymentServicesFA.Models.Response;
using ReceivePaymentServicesFA.Interface.Adapters;
using ReceivePaymentServicesFA.Interface.CosmosDataAdapter;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;

namespace ReceivePaymentServicesFA.Functions;

public class TchStatus
{
    private readonly IPaymentCosmosDBService _cosmosdB;
    private readonly IServiceBusAdapter _serviceBusAdapter;
    private readonly IEvolveRequestHelper _evolveRequestHelper;
    private readonly AppSettings _appSettings;
    private readonly ILogger<TchStatus> log;

    public TchStatus(IPaymentCosmosDBService cosmosdB, IServiceBusAdapter serviceBus, IEvolveRequestHelper evolveRequestHelper,
        IOptions<AppSettings> appSettings, ILogger<TchStatus> logger)
    {
        _cosmosdB = cosmosdB;
        _serviceBusAdapter = serviceBus;
        _evolveRequestHelper = evolveRequestHelper;
        _appSettings = appSettings.Value;
        log = logger;
    }

    /// <summary>
    /// Receives notification from TabaPay whether the transaction was ACCEPTED or REJECTED
    /// </summary>
    /// <param name="req"></param>
    /// <returns>The OK response</returns>
    [Function("TchStatus")]
    [OpenApiOperation(operationId: "TchStatus", tags: new[] { "TchStatus" })]
    [OpenApiRequestBody(contentType: "application/json", bodyType: typeof(TchStatusRequest), Description = "RTPReceive TCH Status", Required = true)]
    [OpenApiResponseWithBody(statusCode: HttpStatusCode.OK, contentType: "application/json", bodyType: typeof(TchStatusResponse), Description = "The OK response")]

    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req)
    {
        try
        {
            // Get request
            var tchStatus = await req.GetJsonBodyAsync<TchStatusRequest>();

            // Original Id
            var instructionId = tchStatus.NetworkID;
            var reasonCode = tchStatus.Status;

            log.LogInformation($"Receieved TchStatus request for instructionId Id: '{instructionId}' and reason code '{reasonCode}'");

            // todo - Retrieve cosmos document based on original Id
            var cosmosDocument = await _cosmosdB.GetItemByInstructionIdAsync(instructionId);

            if (cosmosDocument == null)
            {
                log.LogInformation($"Cosmos document with instruction id {instructionId} not found");

                // Send message to service bus to process again.  The document might not have been created due to timeout issues
                var tchStatusSbMsg = JsonConvert.SerializeObject(tchStatus);
                await SendMessageToServiceBus(tchStatusSbMsg, PaymentRequestConstants.TchStatus);

                return await ActionResultResponseHelper.CreateBadRequestAsync(req.HttpContext);
            }

            // Get last status from Status history
            var last = cosmosDocument.StatusHistory.Last();

            // Prevent duplicate posting
            if ((last.Stage == RequestStage.JHA.ToString() || last.Stage == RequestStage.POSTING.ToString()) && last.Status == RequestStatus.COMPLETED.ToString())
            {
                log.LogInformation($"Duplicate posting not allowed. Transaction stage {last.Stage} with status {last.Status}");
                return await ActionResultResponseHelper.CreateConflictAsync(req.HttpContext, new TchStatusResponse() { Status = "ERROR - Transaction already posted" });
            }

            // Prevent duplicate TchStatus acknowledgement
            if(last.Stage == RequestStage.RTP_API.ToString() && (last.Status == RequestStatus.ACCEPTED.ToString() || last.Status == RequestStatus.REJECTED.ToString()))
            {
                log.LogInformation($"Reason Code {reasonCode} sent for document {cosmosDocument.EvolveId}. " +
                    $" TchStatus has already been acknowledged for this transaction. Status {last.Status}. Info {last.AddInfo}");
                return await ActionResultResponseHelper.CreateConflictAsync(req.HttpContext, new TchStatusResponse() { Status = "ERROR - Transaction already acknowledged" });
            }

            // Pre Checks before proceeding
            if (!PreChecksPassed(cosmosDocument, last))
            {
                // Send message to SB
                var message = new PreCheckFailedRequest { ReasonCode = reasonCode, EvolveId = cosmosDocument.EvolveId, MessageProcessedCount = 0 };
                log.LogInformation($"Sending message to PreCheckFailedProcessing function with message {JsonConvert.SerializeObject(message)}");
                await SendMessageToServiceBus(JsonConvert.SerializeObject(message),  PaymentRequestConstants.PreChecksFailedServiceBusSubject);

                return await ActionResultResponseHelper.CreateOkAsync(req.HttpContext, new TchStatusResponse() { Status = "OK" });
            }

            // Check if reason code is accepted or rejected
            if (!RTPReceiveStatusConstants.IsValidReasonCode(reasonCode))
            {
                log.LogInformation($"TchStatus request for instructionId Id: '{instructionId}' with reason code '{reasonCode}' not recognized");
                return await ActionResultResponseHelper.CreateOkAsync(req.HttpContext, new TchStatusResponse() { Status = "OK" });
            }

            // Determine if the transaction is successful
            bool isSuccess = reasonCode == RTPReceiveStatusConstants.ReasonCodeAccepted;

            // Send message to service bus
            cosmosDocument.Status = isSuccess ? RequestStatus.ACCEPTED.ToString() : RequestStatus.REJECTED.ToString();
            var serviceBusMessage = ServiceBusContentHelper.CreateServiceBusMessage(cosmosDocument, isSuccess, new { reasonCode }, null);
            var serviceBusSubject = isSuccess ? PaymentRequestConstants.SuccessReceiveServiceBusSubject : PaymentRequestConstants.FailureReceiveServiceBusSubject;
            await SendMessageToServiceBus(JsonConvert.SerializeObject(serviceBusMessage), serviceBusSubject);

            // Update cosmos
            cosmosDocument = await PatchTransactionStatus(
                                        RequestStage.RTP_API,
                                        isSuccess ? RequestStatus.ACCEPTED : RequestStatus.REJECTED,
                                        new { reasonCode },
                                        cosmosDocument);

            if (isSuccess)
            {
                // Post to JHA
                var receiveCreditRequest = _evolveRequestHelper.CreateRtpCreditRequest(cosmosDocument.InstructionId, cosmosDocument.EndToEndId,
                    cosmosDocument.Amount, cosmosDocument.FboAccountNumber, _appSettings.RTP_RECEIVE_TRAN_CODE);

                var jhaPostingQueueMessage = new JhaQueueRequest()
                {
                    EvolveId = cosmosDocument.EvolveId,
                    RtpCreditRequest = receiveCreditRequest
                };

                log.LogInformation($"Sending message Service bus topic {_appSettings?.SERVICE_BUS_TOPIC_NAME} to subscription jhaaccountposting");
                await SendMessageToServiceBus(JsonConvert.SerializeObject(jhaPostingQueueMessage), "JHA Posting");
            }

            return await ActionResultResponseHelper.CreateOkAsync(req.HttpContext, new TchStatusResponse() { Status = "OK" });
        }
        catch (JsonException ex)
        {
            log.LogError(ex, "Receive Payment Services Json Deserialization Error: {Message}, {Stack}", ex.Message, ex.StackTrace);
            return await ActionResultResponseHelper.CreateInternalServerErrorAsync(req.HttpContext, new TabaPayResponse()
            {
                Status = PaymentRequestConstants.TabaPayError,
                StatusReason = "Internal error",
                StatusReasonDescription = "An internal error occurred"
            });
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Receive Payment Services function Error: {Message}, {Stack}", ex.Message, ex.StackTrace);
            return await ActionResultResponseHelper.CreateInternalServerErrorAsync(req.HttpContext, new TabaPayResponse()
            {
                Status = PaymentRequestConstants.TabaPayError,
                StatusReason = "Internal error",
                StatusReasonDescription = "An internal error occurred"
            });
        }
    }

    private static bool PreChecksPassed(EvolvePaymentRequest cosmosDocument, StatusHistory last)
    {
        // The transfer checks pass when the LAST pre-check stage (LEDGER) has
        // completed — LIMIT and SCREENING must have completed before it.
        return !string.IsNullOrWhiteSpace(cosmosDocument.FintechId) &&
                !string.IsNullOrWhiteSpace(cosmosDocument.FboAccountNumber) &&
                last.Stage == TransferStageConstants.Ledger &&
                last.Status == RequestStatus.COMPLETED.ToString();
    }

    private async Task SendMessageToServiceBus(string content, string subject)
    {
        string topicName = _appSettings?.SERVICE_BUS_TOPIC_NAME;
        log.LogInformation($"Sending message to service bus topic: {topicName}");
        var serviceBusRequest = new ServiceBusRequest()
        {
            Content = content,
            Subject = subject,
            QueueName = topicName
        };

        log.LogInformation($"Message sent to service bus topic {topicName}");

        // Send message to service bus queue
        await _serviceBusAdapter.SendMessage(serviceBusRequest);
    }

    private async Task<EvolvePaymentRequest> PatchTransactionStatus(RequestStage stage, RequestStatus status, object additionalInfo, EvolvePaymentRequest request)
    {
        // Patch cosmos item
        var patchOperationStatus = EvolveRequestHelper.GetStatusPatchOperation(stage, status, additionalInfo);

        return await _cosmosdB.PatchItemAsync(request, patchOperationStatus);
    }
}