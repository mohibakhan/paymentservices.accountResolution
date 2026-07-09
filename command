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
    public async Task ProcessAsync_AfterGatewayCall_AppendsScreeningAndLimitsStatusToHistory()
    {
        var payment = TestDataBuilder.AnEvolvePaymentAtStage(RequestStage.RTP_API);

        await _sut.ProcessAsync(payment);

        payment.StatusHistory.Should().Contain(history =>
            history.Stage == RequestStage.ACCOUNTLOOKUP.ToString()
            && history.Status == RequestStatus.COMPLETED.ToString()
            && history.AddInfo != null
            && history.AddInfo.ToString()!.Contains("Screening and limits passed", StringComparison.Ordinal));
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
