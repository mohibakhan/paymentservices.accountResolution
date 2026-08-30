using System;
using System.Linq;
using System.Text;
using Newtonsoft.Json;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Azure.Functions.Worker;
using ReceivePaymentServicesFA.Helpers;
using ReceivePaymentServicesFA.Settings;
using ReceivePaymentServicesFA.Constants;
using ReceivePaymentServicesFA.Interface;
using Evolve.Digital.Shared.Models.Payments;
using ReceivePaymentServicesFA.Models.Request;
using ReceivePaymentServicesFA.Interface.Adapters;
using ReceivePaymentServicesFA.Interface.CosmosDataAdapter;

namespace ReceivePaymentServicesFA.Functions;

public class PreCheckFailedProcessing
{
    private readonly IPaymentCosmosDBService _cosmosdB;
    private readonly IServiceBusAdapter _serviceBusAdapter;
    private readonly AppSettings _appSettings;
    private readonly ILogger<PreCheckFailedProcessing> _logger;
    private readonly IEvolveRequestHelper _evolveRequestHelper;

    public PreCheckFailedProcessing(IPaymentCosmosDBService cosmosdB, IServiceBusAdapter serviceBusAdapter, IEvolveRequestHelper evolveRequestHelper,
                  IOptions<AppSettings> appSettings, ILogger<PreCheckFailedProcessing> logger)
    {
        _cosmosdB = cosmosdB;
        _serviceBusAdapter = serviceBusAdapter;
        _appSettings = appSettings.Value;
        _evolveRequestHelper = evolveRequestHelper;
        _logger = logger;
    }

    [Function(nameof(PreCheckFailedProcessing))]
    public async Task Run(
        [ServiceBusTrigger(topicName: "%rtpReceive:AppSettings:SERVICE_BUS_TOPIC_NAME%",
                       subscriptionName: "%rtpReceive:AppSettings:SERVICE_BUS_PRECHECK_FAILED_SUBSCRIPTION_NAME%",
                       Connection = "rtpReceive:AppSettings:SERVICE_BUS_CONNSTRING", IsBatched =true)]
         ServiceBusReceivedMessage[] messages,
         ServiceBusMessageActions messageActions)
    {
        foreach (var message in messages)
        {
            await ProcessMessageAsync(message, messageActions);
        }
    }

    private async Task ProcessMessageAsync(ServiceBusReceivedMessage message, ServiceBusMessageActions messageActions)
    {
        try
        {
            _logger.LogInformation("message received");
            string payload = Encoding.UTF8.GetString(message.Body);
            _logger.LogInformation($"Pre-check failed processing function triggered for message: {payload}");

            var queueItem = JsonConvert.DeserializeObject<PreCheckFailedRequest>(payload);
            var reasonCode = queueItem.ReasonCode;
            var evolveId = queueItem.EvolveId;
            var messageProcessedCount = queueItem.MessageProcessedCount;

            var cosmosDocument = await RetrieveCosmosDocumentAsync(evolveId, message, messageActions);
            if (cosmosDocument != null)
            {
                // Update cosmos db with the reason code if previous stages are updated, otherwise re-submit
                _logger.LogInformation($"Cosmos document retrieved.  Updating document status. Received reason code {reasonCode} for document with evolve Id {evolveId}." +
                    $" Message Processing count {messageProcessedCount}");
                // Get last status from Status history
                var last = cosmosDocument.StatusHistory.Last();

                // Transaction is still updating - resubmit message
                if (!TransferStageConstants.IsTransferStage(last.Stage))
                {
                    // Get message count
                    if (messageProcessedCount > _appSettings.PRECHECK_FAILED_PROCESSING_COUNT_LIMIT)
                    {
                        _logger.LogInformation($"Message processing execution count has reached {messageProcessedCount}. Manual intervention required.");

                        // reject message Send message to service bus
                        cosmosDocument.Status = RequestStatus.REJECTED.ToString();
                        var additionalInfo = new { ReasonCodeReceived = reasonCode, expectedReasonCode = RTPReceiveStatusConstants.ReasonCodeRejected, messageProcessedCount, comments = "Fraud/Sanctions not passed" };
                        var serviceBusMessage = ServiceBusContentHelper.CreateServiceBusMessage(cosmosDocument, false, additionalInfo, null);
                        var serviceBusSubject = PaymentRequestConstants.FailureReceiveServiceBusSubject;
                        await SendMessageToServiceBus(JsonConvert.SerializeObject(serviceBusMessage), serviceBusSubject);

                        // Update cosmos
                        cosmosDocument = await PatchTransactionStatus(
                                                    RequestStage.RTP_API,
                                                    RequestStatus.REJECTED,
                                                    additionalInfo,
                                                    cosmosDocument);

                    }
                    else
                    {
                        await HandleMessageResubmitAsync(message, messageActions);
                    }
                }

                // Transaction has the lastest status - continue with Precheck
                if (TransferStageConstants.IsTransferStage(last.Stage))
                {
                    // Check if the transfer checks (limit, screening, ledger) completed
                    if (PreChecksPassed(cosmosDocument, last))
                    {
                        // Submit to JHA if reason code ACTC - Determine if the transaction is successful
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

                            _logger.LogInformation($"Sending message Service bus topic {_appSettings?.SERVICE_BUS_TOPIC_NAME} to subscription jhaaccountposting");
                            await SendMessageToServiceBus(JsonConvert.SerializeObject(jhaPostingQueueMessage), "JHA Posting");
                        }
                    }
                    else
                    {
                        // Pre check still failed - Update Cosmos DB with rejected irrespective of TchStatus Code
                        cosmosDocument.Status = RequestStatus.REJECTED.ToString();
                        var additionalInfo = new { ReasonCodeExpected = RTPReceiveStatusConstants.ReasonCodeRejected, ReasonCodeReceived = reasonCode, PreCheckStatus = "Failed" };
                        var serviceBusMessage = ServiceBusContentHelper.CreateServiceBusMessage(cosmosDocument, false, additionalInfo, null);
                        var serviceBusSubject = PaymentRequestConstants.FailureReceiveServiceBusSubject;
                        await SendMessageToServiceBus(JsonConvert.SerializeObject(serviceBusMessage), serviceBusSubject);

                        // Update cosmos
                        cosmosDocument = await PatchTransactionStatus(
                                                    RequestStage.RTP_API,
                                                    RequestStatus.REJECTED,
                                                    additionalInfo,
                                                    cosmosDocument);

                        await messageActions.CompleteMessageAsync(message);
                    }
                }
            }

        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(ex, message, messageActions);
        }
    }

    private async Task HandleMessageResubmitAsync(ServiceBusReceivedMessage message, ServiceBusMessageActions messageActions)
    {
        string payload = Encoding.UTF8.GetString(message.Body);
        var deserializedPayload = JsonConvert.DeserializeObject<PreCheckFailedRequest>(payload);
        // Counter message count
        int updatedMessageCount = deserializedPayload.MessageProcessedCount + 1;
        var messageBody = new PreCheckFailedRequest
        {
            EvolveId = deserializedPayload.EvolveId,
            ReasonCode = deserializedPayload.ReasonCode,
            MessageProcessedCount = updatedMessageCount
        };
        var sbMessage = JsonConvert.SerializeObject(messageBody);
        _logger.LogInformation($"Resubmitting message: {sbMessage}");

        ServiceBusMessage resubmittableMessage = new ServiceBusMessage(Encoding.UTF8.GetBytes(sbMessage))
        {
            ScheduledEnqueueTime = DateTime.UtcNow.AddMinutes(_appSettings.PRECHECK_FAILED_RESUBMISSION_MINUTES),
            Subject = PaymentRequestConstants.PreChecksFailedServiceBusSubject
        };

        var client = new ServiceBusClient(_appSettings.SERVICE_BUS_CONNSTRING);
        var sender = client.CreateSender(_appSettings.SERVICE_BUS_TOPIC_NAME);
        await sender.SendMessageAsync(resubmittableMessage);
        await messageActions.CompleteMessageAsync(message);
    }

    private async Task<EvolvePaymentRequest> RetrieveCosmosDocumentAsync(string evolveId, ServiceBusReceivedMessage message, ServiceBusMessageActions messageActions)
    {
        _logger.LogInformation($"Retrieving cosmos document for evolve Id: {evolveId}");
        var cosmosDocument = await _cosmosdB.GetItemByEvolveIdAsync(evolveId);
        if (cosmosDocument == null)
        {
            _logger.LogInformation($"Cosmos Document not found for evolve Id {evolveId}. Sending message to DLQ");
            await messageActions.DeadLetterMessageAsync(message, null, $"Cosmos Document not found for evolve Id {evolveId}");
            return null;
        }
        return cosmosDocument;
    }

    private async Task HandleExceptionAsync(Exception ex, ServiceBusReceivedMessage message, ServiceBusMessageActions messageActions)
    {
        _logger.LogError($"Exception occurred in JHAPosting, Message: {ex.Message} || StackTrace: {ex.StackTrace}");
        await messageActions.DeadLetterMessageAsync(message, null,
            $"Reason: Unhandled Exception While processing message: {ex.Message}",
            $"Description: Stack Trace: {ex.StackTrace}");
    }

    private async Task SendMessageToServiceBus(string content, string subject)
    {
        string topicName = _appSettings?.SERVICE_BUS_TOPIC_NAME;
        _logger.LogInformation($"Sending message to service bus topic: {topicName}");
        var serviceBusRequest = new ServiceBusRequest()
        {
            Content = content,
            Subject = subject,
            QueueName = topicName
        };

        _logger.LogInformation($"Message sent to service bus topic {topicName}");

        // Send message to service bus queue
        await _serviceBusAdapter.SendMessage(serviceBusRequest);
    }

    private async Task<EvolvePaymentRequest> PatchTransactionStatus(RequestStage stage, RequestStatus status, object additionalInfo, EvolvePaymentRequest request)
    {
        // Patch cosmos item
        var patchOperationStatus = EvolveRequestHelper.GetStatusPatchOperation(stage, status, additionalInfo);

        return await _cosmosdB.PatchItemAsync(request, patchOperationStatus);
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
}
