[Fact]
public async Task ProcessAsync_AfterGatewayCall_AppendsGatewaySubmittedStatusToHistory()
{
    var payment = TestDataBuilder.AnEvolvePaymentAtStage(RequestStage.RTP_API);

    await _sut.ProcessAsync(payment);

    payment.StatusHistory.Should().Contain(history =>
        history.Stage == RequestStage.ACCOUNTLOOKUP.ToString()
        && history.Status == RequestStatus.INITIATED.ToString()
        && history.AddInfo != null
        && history.AddInfo.ToString()!.Contains("Submitted to Gateway", StringComparison.Ordinal));
}

[Fact]
public async Task ProcessAsync_AfterGatewayCall_PatchesGatewaySubmittedStatusEntry()
{
    var payment = TestDataBuilder.AnEvolvePaymentAtStage(RequestStage.RTP_API);

    await _sut.ProcessAsync(payment);

    _paymentCosmosDB.Verify(c => c.PatchItemAsync(
            It.IsAny<EvolvePaymentRequest>(),
            It.IsAny<List<PatchOperation>>()),
        Times.Once);
}
