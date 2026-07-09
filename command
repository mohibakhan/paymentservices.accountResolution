using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaymentServices.RTPSend.Constants;
using PaymentServices.RTPSend.Exceptions;
using PaymentServices.RTPSend.Helpers;
using PaymentServices.RTPSend.Interface.Adapters;
using PaymentServices.RTPSend.Interface.Services;
using PaymentServices.RTPSend.Models.Cosmos;
using PaymentServices.RTPSend.Models.Domain;
using PaymentServices.RTPSend.Settings;

namespace PaymentServices.RTPSend.Services;

public interface IPaymentOrchestrator
{
    /// <summary>
    /// Runs RTPSend's portion of the pipeline: ACCOUNTLOOKUP (partner-ledger)
    /// then calls Gateway /tptch/send. The async pipeline (AccountResolution →
    /// Transfer) and the rtpsend-outcome handler take it from there.
    /// </summary>
    Task<EvolvePaymentRequest> ProcessAsync(EvolvePaymentRequest payment, CancellationToken cancellationToken = default);

    /// <summary>
    /// Resumes from whatever stage the payment is currently in (stage-aware SB
    /// redelivery). RTPSend now only owns ACCOUNTLOOKUP → Gateway hand-off.
    /// </summary>
    Task<EvolvePaymentRequest> ResumeFromAsync(EvolvePaymentRequest payment, CancellationToken cancellationToken = default);
}

public sealed class PaymentOrchestrator : IPaymentOrchestrator
{
    private readonly IPartnerLedgerSystem _partnerLedger;
    private readonly IGatewayClient _gatewayClient;
    private readonly IPaymentCosmosDBAdapter _paymentCosmosDB;
    private readonly RtpSendSettings _settings;
    private readonly ILogger<PaymentOrchestrator> _logger;

    public PaymentOrchestrator(
        IPartnerLedgerSystem partnerLedger,
        IGatewayClient gatewayClient,
        IPaymentCosmosDBAdapter paymentCosmosDB,
        IOptions<RtpSendSettings> settings,
        ILogger<PaymentOrchestrator> logger)
    {
        _partnerLedger = partnerLedger;
        _gatewayClient = gatewayClient;
        _paymentCosmosDB = paymentCosmosDB;
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task<EvolvePaymentRequest> ProcessAsync(
        EvolvePaymentRequest payment, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Full pipeline for evolveId {EvolveId}", payment.EvolveId);
        return await RunStagesAsync(payment, startStage: RequestStage.ACCOUNTLOOKUP, cancellationToken);
    }

    public async Task<EvolvePaymentRequest> ResumeFromAsync(
        EvolvePaymentRequest payment, CancellationToken cancellationToken = default)
    {
        var startStage = DetermineResumeStage(payment);
        if (startStage is null)
        {
            _logger.LogInformation(
                "Payment {EvolveId} is already in terminal state ({Status}); nothing to resume.",
                payment.EvolveId, payment.Status);
            return payment;
        }

        _logger.LogInformation(
            "Resuming evolveId {EvolveId} from stage {Stage}", payment.EvolveId, startStage);
        return await RunStagesAsync(payment, startStage.Value, cancellationToken);
    }

    /// <summary>
    /// Reads payment.Stage + payment.Status from the persisted Cosmos document
    /// and decides which stage to start from. If already completed or terminally
    /// failed, returns null.
    /// </summary>
    private static RequestStage? DetermineResumeStage(EvolvePaymentRequest payment)
    {
        // Already fully processed — no resume needed.
        if (payment.Status == RequestStatus.COMPLETED.ToString())
            return null;

        // Terminal NSF failure — no resume, ever. The funds situation isn't
        // going to fix itself via retry.
        if (payment.Status == RequestStatus.FAILED_NSF.ToString())
            return null;

        // Map last attempted stage → which stage to retry from. RTPSend now
        // only owns ACCOUNTLOOKUP + the Gateway hand-off, so every non-terminal
        // resume restarts at ACCOUNTLOOKUP (idempotent: partner-ledger lookup
        // and Gateway dedupe both tolerate replays).
        return payment.Stage switch
        {
            nameof(RequestStage.RTP_API) => RequestStage.ACCOUNTLOOKUP,
            nameof(RequestStage.ACCOUNTLOOKUP) => RequestStage.ACCOUNTLOOKUP,
            _ => RequestStage.ACCOUNTLOOKUP
        };
    }

    private async Task<EvolvePaymentRequest> RunStagesAsync(
        EvolvePaymentRequest payment, RequestStage startStage, CancellationToken cancellationToken)
    {
        // ----- Stage: PartnerLedger (ACCOUNTLOOKUP) -----------------------
        // Resolves source account → FBO account and enriches the doc.
        if (startStage <= RequestStage.ACCOUNTLOOKUP)
            payment = await _partnerLedger.PerformAccountLookupUpdate(payment);

        // ----- Stage: call Gateway /tptch/send ----------------------------
        // Gateway validates/dedupes/persists and publishes to the async
        // pipeline (AccountResolution → Transfer). The eventual outcome
        // (TransferCompleted/Failed/AccountResolutionFailed) comes back to
        // RTPSend via the rtpsend-outcome subscription, where TabaPay runs.
        await _gatewayClient.SendAsync(payment, cancellationToken);

        // Patch status: handed off to Gateway. Stage stays at ACCOUNTLOOKUP
        // (its last RTPSend-owned stage); status INITIATED signals "in flight,
        // awaiting pipeline outcome". No outcome envelope is published here.
        var gatewaySubmissionPatches = EvolvePaymentRequestHelper.GetStatusPatchOperation(
            RequestStage.ACCOUNTLOOKUP,
            RequestStatus.INITIATED,
            additionalInfo: new { Message = "Submitted to Gateway tptch/send" });

        await _paymentCosmosDB.PatchItemAsync(payment, gatewaySubmissionPatches);

        var screeningPassedPatches = EvolvePaymentRequestHelper.GetStatusPatchOperation(
            RequestStage.ACCOUNTLOOKUP,
            RequestStatus.COMPLETED,
            additionalInfo: new { Message = "Screening and limits passed" });

        await _paymentCosmosDB.PatchItemAsync(payment, screeningPassedPatches);

        payment.Stage = RequestStage.ACCOUNTLOOKUP.ToString();
        payment.Status = RequestStatus.INITIATED.ToString();

        _logger.LogInformation(
            "Payment {EvolveId} submitted to Gateway; awaiting pipeline outcome.",
            payment.EvolveId);

        return payment;
    }
}



using FluentAssertions;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using PaymentServices.RTPSend.Interface.Adapters;
using PaymentServices.RTPSend.Interface.Services;
using PaymentServices.RTPSend.Models.Cosmos;
using PaymentServices.RTPSend.Models.Domain;
using PaymentServices.RTPSend.Services;
using PaymentServices.RTPSend.Settings;
using PaymentServices.RTPSend.UnitTests.TestHelpers;

namespace PaymentServices.RTPSend.UnitTests.Services;

/// <summary>
/// Tests for the refactored orchestrator. RTPSend now owns only two steps:
///   1. ACCOUNTLOOKUP (partner-ledger enrichment)
///   2. call Gateway /tptch/send, then patch the Cosmos status and stop.
/// Limits/ledger/screening moved to the Transfer service; TabaPay moved to the
/// rtpsend-outcome handler. The orchestrator no longer publishes envelopes.
/// </summary>
public class PaymentOrchestratorTests
{
    private readonly Mock<IPartnerLedgerSystem> _partnerLedger = new();
    private readonly Mock<IGatewayClient> _gatewayClient = new();
    private readonly Mock<IPaymentCosmosDBAdapter> _paymentCosmosDB = new();
    private readonly PaymentOrchestrator _sut;

    public PaymentOrchestratorTests()
    {
        _partnerLedger
            .Setup(p => p.PerformAccountLookupUpdate(It.IsAny<EvolvePaymentRequest>()))
            .ReturnsAsync((EvolvePaymentRequest p) => p);

        _gatewayClient
            .Setup(g => g.SendAsync(It.IsAny<EvolvePaymentRequest>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        _paymentCosmosDB
            .Setup(c => c.PatchItemAsync(
                It.IsAny<EvolvePaymentRequest>(), It.IsAny<List<PatchOperation>>()))
            .ReturnsAsync((EvolvePaymentRequest p, List<PatchOperation> _) => p);

        _sut = new PaymentOrchestrator(
            _partnerLedger.Object,
            _gatewayClient.Object,
            _paymentCosmosDB.Object,
            Options.Create(new RtpSendSettings()),
            Mock.Of<ILogger<PaymentOrchestrator>>());
    }

    // -------------------------------------------------------------------------
    // ProcessAsync — ACCOUNTLOOKUP then Gateway call
    // -------------------------------------------------------------------------

    [Fact]
    public async Task ProcessAsync_RunsAccountLookupThenCallsGateway()
    {
        var payment = TestDataBuilder.AnEvolvePaymentAtStage(RequestStage.RTP_API);

        await _sut.ProcessAsync(payment);

        _partnerLedger.Verify(p => p.PerformAccountLookupUpdate(payment), Times.Once);
        _gatewayClient.Verify(g => g.SendAsync(payment, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ProcessAsync_AfterGatewayCall_PatchesStatusToInitiated()
    {
        var payment = TestDataBuilder.AnEvolvePaymentAtStage(RequestStage.RTP_API);

        await _sut.ProcessAsync(payment);

        _paymentCosmosDB.Verify(c => c.PatchItemAsync(
                It.IsAny<EvolvePaymentRequest>(),
                It.Is<List<PatchOperation>>(ops =>
                    ops.Any(o => o.OperationType == PatchOperationType.Replace))),
            Times.AtLeastOnce);

        payment.Stage.Should().Be(RequestStage.ACCOUNTLOOKUP.ToString());
        payment.Status.Should().Be(RequestStatus.INITIATED.ToString());
    }

    [Fact]
    public async Task ProcessAsync_AfterGatewayCall_PatchesAnAdditionalAccountLookupStatusEntry()
    {
        var payment = TestDataBuilder.AnEvolvePaymentAtStage(RequestStage.RTP_API);

        await _sut.ProcessAsync(payment);

        _paymentCosmosDB.Verify(c => c.PatchItemAsync(
                It.IsAny<EvolvePaymentRequest>(),
                It.IsAny<List<PatchOperation>>()),
            Times.Exactly(2));
    }

    [Fact]
    public async Task ProcessAsync_WhenGatewayCallFails_DoesNotPatchStatus()
    {
        _gatewayClient
            .Setup(g => g.SendAsync(It.IsAny<EvolvePaymentRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new GatewayCallException("gateway 500", 500));

        var payment = TestDataBuilder.AnEvolvePaymentAtStage(RequestStage.RTP_API);

        await FluentActions.Invoking(() => _sut.ProcessAsync(payment))
            .Should().ThrowAsync<GatewayCallException>();

        _paymentCosmosDB.Verify(c => c.PatchItemAsync(
                It.IsAny<EvolvePaymentRequest>(), It.IsAny<List<PatchOperation>>()),
            Times.Never);
    }

    [Fact]
    public async Task ProcessAsync_WhenGatewayCallFails_PropagatesException()
    {
        _gatewayClient
            .Setup(g => g.SendAsync(It.IsAny<EvolvePaymentRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new GatewayCallException("gateway unavailable"));

        var payment = TestDataBuilder.AnEvolvePaymentAtStage(RequestStage.RTP_API);

        await FluentActions.Invoking(() => _sut.ProcessAsync(payment))
            .Should().ThrowAsync<GatewayCallException>();
    }

    // -------------------------------------------------------------------------
    // ResumeFromAsync — stage-aware resume (RTPSend only owns ACCOUNTLOOKUP now)
    // -------------------------------------------------------------------------

    [Fact]
    public async Task ResumeFromAsync_WhenStageIsRtpApi_RunsAccountLookupAndGateway()
    {
        var payment = TestDataBuilder.AnEvolvePaymentAtStage(
            stage: RequestStage.RTP_API, status: RequestStatus.RECEIVED);

        await _sut.ResumeFromAsync(payment);

        _partnerLedger.Verify(p => p.PerformAccountLookupUpdate(payment), Times.Once);
        _gatewayClient.Verify(g => g.SendAsync(payment, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ResumeFromAsync_WhenStageIsAccountLookup_RerunsAccountLookupAndGateway()
    {
        var payment = TestDataBuilder.AnEvolvePaymentAtStage(
            stage: RequestStage.ACCOUNTLOOKUP, status: RequestStatus.FAILED);

        await _sut.ResumeFromAsync(payment);

        _partnerLedger.Verify(p => p.PerformAccountLookupUpdate(payment), Times.Once);
        _gatewayClient.Verify(g => g.SendAsync(payment, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ResumeFromAsync_WhenAlreadyCompleted_DoesNothing()
    {
        var payment = TestDataBuilder.AnEvolvePaymentAtStage(
            stage: RequestStage.ACCOUNTLOOKUP, status: RequestStatus.COMPLETED);

        var result = await _sut.ResumeFromAsync(payment);

        result.Should().BeSameAs(payment);
        _partnerLedger.VerifyNoOtherCalls();
        _gatewayClient.VerifyNoOtherCalls();
        _paymentCosmosDB.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ResumeFromAsync_WhenTerminalNsf_DoesNothing()
    {
        var payment = TestDataBuilder.AnEvolvePaymentAtStage(
            stage: RequestStage.ACCOUNTLOOKUP, status: RequestStatus.FAILED_NSF);

        var result = await _sut.ResumeFromAsync(payment);

        result.Should().BeSameAs(payment);
        _partnerLedger.VerifyNoOtherCalls();
        _gatewayClient.VerifyNoOtherCalls();
        _paymentCosmosDB.VerifyNoOtherCalls();
    }
}
