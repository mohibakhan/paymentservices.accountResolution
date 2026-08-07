2026-08-07T13:30:22.154 [Information] Reading functions metadata (Custom)
2026-08-07T13:30:22.198 [Information] 0 functions found (Custom)
2026-08-07T13:30:22.208 [Information] 14 functions loaded
2026-08-07T13:30:22.217 [Information] ScriptJobHostOptions
{
  "FileWatchingEnabled": true,
  "FileLoggingMode": "DebugOnly",
  "FunctionTimeout": "00:30:00",
  "TelemetryMode": "ApplicationInsights"
}
2026-08-07T13:30:22.217 [Information] ApplicationInsightsLoggerOptions
{
  "SamplingSettings": {
    "EvaluationInterval": "00:00:15",
    "InitialSamplingPercentage": 100.0,
    "MaxSamplingPercentage": 100.0,
    "MaxTelemetryItemsPerSecond": 20.0,
    "MinSamplingPercentage": 0.1,
    "MovingAverageRatio": 0.25,
    "SamplingPercentageDecreaseTimeout": "00:02:00",
    "SamplingPercentageIncreaseTimeout": "00:15:00"
  },
  "SamplingExcludedTypes": "Request",
  "SamplingIncludedTypes": null,
  "SnapshotConfiguration": null,
  "EnablePerformanceCountersCollection": true,
  "HttpAutoCollectionOptions": {
    "EnableHttpTriggerExtendedInfoCollection": true,
    "EnableW3CDistributedTracing": true,
    "EnableResponseHeaderInjection": true
  },
  "LiveMetricsInitializationDelay": "00:00:15",
  "EnableLiveMetrics": true,
  "EnableLiveMetricsFilters": true,
  "EnableQueryStringTracing": false,
  "EnableDependencyTracking": true,
  "DependencyTrackingOptions": null,
  "TokenCredentialOptions": null,
  "DiagnosticsEventListenerLogLevel": null,
  "EnableAutocollectedMetricsExtractor": false,
  "EnableMetricsCustomDimensionOptimization": false,
  "EnableAdaptiveSamplingDelay": true,
  "AdaptiveSamplingInitializationDelay": "00:00:15"
}
2026-08-07T13:30:22.217 [Information] LoggerFilterOptions
{
  "MinLevel": "None",
  "Rules": [
    {
      "ProviderName": null,
      "CategoryName": null,
      "LogLevel": null,
      "Filter": "<AddFilter>b__0"
    },
    {
      "ProviderName": "Microsoft.Azure.WebJobs.Script.WebHost.Diagnostics.WebHostSystemLoggerProvider",
      "CategoryName": null,
      "LogLevel": "None",
      "Filter": null
    },
    {
      "ProviderName": "Microsoft.Azure.WebJobs.Script.WebHost.Diagnostics.WebHostSystemLoggerProvider",
      "CategoryName": null,
      "LogLevel": null,
      "Filter": "<AddFilter>b__0"
    },
    {
      "ProviderName": null,
      "CategoryName": null,
      "LogLevel": null,
      "Filter": "<AddFilter>b__0"
    },
    {
      "ProviderName": "Microsoft.Azure.WebJobs.Script.WebHost.Diagnostics.SystemLoggerProvider",
      "CategoryName": null,
      "LogLevel": "None",
      "Filter": null
    },
    {
      "ProviderName": "Microsoft.Azure.WebJobs.Script.WebHost.Diagnostics.SystemLoggerProvider",
      "CategoryName": null,
      "LogLevel": null,
      "Filter": "<AddFilter>b__0"
    }
  ]
}
2026-08-07T13:30:22.217 [Information] HttpWorkerOptions
{
  "Type": 0,
  "Description": null,
  "Arguments": null,
  "Port": 50520,
  "IsPortManuallySet": false,
  "EnableForwardingHttpRequest": false,
  "EnableProxyingHttpRequest": false,
  "InitializationTimeout": "00:00:30",
  "CustomRoutesEnabled": false,
  "Http": null
}
2026-08-07T13:30:22.217 [Information] ScriptJobHostOptions
{
  "FileWatchingEnabled": true,
  "FileLoggingMode": "DebugOnly",
  "FunctionTimeout": "00:30:00",
  "TelemetryMode": "ApplicationInsights"
}
2026-08-07T13:30:22.217 [Information] FunctionResultAggregatorOptions
{
  "BatchSize": 1000,
  "FlushTimeout": "00:00:30",
  "IsEnabled": true
}
2026-08-07T13:30:22.217 [Information] ConcurrencyOptions
{
  "DynamicConcurrencyEnabled": false,
  "MaximumFunctionConcurrency": 500,
  "CPUThreshold": 0.8,
  "SnapshotPersistenceEnabled": true
}
2026-08-07T13:30:22.217 [Information] ServiceBusOptions
{
  "ClientRetryOptions": {
    "Mode": "Exponential",
    "TryTimeout": "00:01:00",
    "Delay": "00:00:00.8000000",
    "MaxDelay": "00:01:00",
    "MaxRetries": 3
  },
  "TransportType": "AmqpTcp",
  "WebProxy": "",
  "AutoCompleteMessages": false,
  "PrefetchCount": 0,
  "MaxAutoLockRenewalDuration": "00:05:00",
  "MaxConcurrentCalls": 16,
  "MaxConcurrentSessions": 8,
  "MaxConcurrentCallsPerSession": 1,
  "MaxMessageBatchSize": 10,
  "MinMessageBatchSize": 1,
  "MaxBatchWaitTime": "00:00:30",
  "SessionIdleTimeout": "",
  "EnableCrossEntityTransactions": false
}
2026-08-07T13:30:22.217 [Information] SingletonOptions
{
  "LockPeriod": "00:00:15",
  "ListenerLockPeriod": "00:01:00",
  "LockAcquisitionTimeout": "10675199.02:48:05.4775807",
  "LockAcquisitionPollingInterval": "00:00:05",
  "ListenerLockRecoveryPollingInterval": "00:01:00"
}
2026-08-07T13:30:22.217 [Information] TimerTriggerPlatformOptions
{
  "NonCronScheduleBehavior": "Allow"
}
2026-08-07T13:30:22.217 [Information] ScaleOptions
{
  "ScaleMetricsMaxAge": "00:02:00",
  "ScaleMetricsSampleInterval": "00:00:10",
  "MetricsPurgeEnabled": true,
  "IsTargetScalingEnabled": true,
  "IsRuntimeScalingEnabled": false
}
2026-08-07T13:30:22.219 [Information] Starting JobHost
2026-08-07T13:30:22.239 [Information] Starting Host (HostId=fa-pmtsvc-rtpsend-prod-eastus, InstanceId=23253211-eec7-4f77-9298-3e1b8cc2ceba, Version=4.1052.300.26370, ProcessId=3372, AppDomainId=1, InDebugMode=True, InDiagnosticMode=False, FunctionsExtensionVersion=~4)
2026-08-07T13:30:22.280 [Information] Generating 14 job function(s)
2026-08-07T13:30:22.284 [Information] Worker process started and initialized.
2026-08-07T13:30:22.322 [Information] Found the following functions:
Host.Functions.CreatePayment
Host.Functions.GetPayment_evolveId
Host.Functions.GetPayment_paymentReference
Host.Functions.HandlePaymentOutcome
Host.Functions.HandleTabaPayRetry
Host.Functions.HandleTabaPayWebhook
Host.Functions.Health
Host.Functions.ProcessPayment
Host.Functions.RenderOAuth2Redirect
Host.Functions.RenderOpenApiDocument
Host.Functions.RenderSwaggerDocument
Host.Functions.RenderSwaggerUI
Host.Functions.RetryFailedPayments
Host.Functions.StubTabaPay
2026-08-07T13:30:22.328 [Information] The 'AutoCompleteMessages' option has been overriden to 'True' value for 'Functions.HandlePaymentOutcome' function.
2026-08-07T13:30:22.342 [Information] The 'AutoCompleteMessages' option has been overriden to 'True' value for 'Functions.HandleTabaPayRetry' function.
2026-08-07T13:30:22.342 [Information] The 'AutoCompleteMessages' option has been overriden to 'True' value for 'Functions.HandleTabaPayWebhook' function.
2026-08-07T13:30:22.342 [Information] The 'AutoCompleteMessages' option has been overriden to 'True' value for 'Functions.ProcessPayment' function.
2026-08-07T13:30:22.344 [Information] Initializing function HTTP routes
Mapped function route 'api/CreatePayment' [post] to 'CreatePayment'
Mapped function route 'api/evolveId/{evolveId}' [get] to 'GetPayment_evolveId'
Mapped function route 'api/paymentReference/{paymentReference}' [get] to 'GetPayment_paymentReference'
Mapped function route 'api/Health' [get] to 'Health'
Mapped function route 'api/oauth2-redirect.html' [GET] to 'RenderOAuth2Redirect'
Mapped function route 'api/openapi/{version}.{extension}' [GET] to 'RenderOpenApiDocument'
Mapped function route 'api/swagger.{extension}' [GET] to 'RenderSwaggerDocument'
Mapped function route 'api/swagger/ui' [GET] to 'RenderSwaggerUI'
Mapped function route 'api/stub/tabapay' [post] to 'StubTabaPay'
2026-08-07T13:30:22.349 [Information] Host initialized (104ms)
2026-08-07T13:30:22.419 [Information] HttpOptions
{
  "DynamicThrottlesEnabled": false,
  "EnableChunkedRequestBinding": false,
  "MaxConcurrentRequests": -1,
  "MaxOutstandingRequests": -1,
  "RoutePrefix": "api"
}
2026-08-07T13:30:22.858 [Information] Host started (617ms)
2026-08-07T13:30:22.858 [Information] Job host started
2026-08-07T13:31:04.735 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 51362,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T13:31:05.271 [Information] HttpOptions
{
  "DynamicThrottlesEnabled": false,
  "EnableChunkedRequestBinding": false,
  "MaxConcurrentRequests": -1,
  "MaxOutstandingRequests": -1,
  "RoutePrefix": "api"
}
2026-08-07T13:31:05.271 [Information] ServiceBusOptions
{
  "ClientRetryOptions": {
    "Mode": "Exponential",
    "TryTimeout": "00:01:00",
    "Delay": "00:00:00.8000000",
    "MaxDelay": "00:01:00",
    "MaxRetries": 3
  },
  "TransportType": "AmqpTcp",
  "WebProxy": "",
  "AutoCompleteMessages": false,
  "PrefetchCount": 0,
  "MaxAutoLockRenewalDuration": "00:05:00",
  "MaxConcurrentCalls": 16,
  "MaxConcurrentSessions": 8,
  "MaxConcurrentCallsPerSession": 1,
  "MaxMessageBatchSize": 10,
  "MinMessageBatchSize": 1,
  "MaxBatchWaitTime": "00:00:30",
  "SessionIdleTimeout": "",
  "EnableCrossEntityTransactions": false
}
2026-08-07T13:31:05.271 [Information] ConcurrencyOptions
{
  "DynamicConcurrencyEnabled": false,
  "MaximumFunctionConcurrency": 500,
  "CPUThreshold": 0.8,
  "SnapshotPersistenceEnabled": true
}
2026-08-07T13:31:06.765 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 53398,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T13:35:07.249 [Information] Host lock lease acquired by instance ID '31e6fd1e6b5310b6b2b5f7a59398990c'.
2026-08-07T13:35:22.920 [Information] The next 5 occurrences of the 'RetryFailedPayments' schedule (Cron: '0 0,5,10,15,20,25,30,35,40,45,50,55 * * * *') will be:
08/07/2026 13:40:00Z
08/07/2026 13:45:00Z
08/07/2026 13:50:00Z
08/07/2026 13:55:00Z
08/07/2026 14:00:00Z
2026-08-07T13:40:00.013 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T13:39:59.9979096+00:00', Id=4d4dd283-7ca4-42e1-981e-8d90a1304030)
2026-08-07T13:40:00.017 [Information] Trigger Details: ScheduleStatus: {"Last":"2026-08-07T13:35:00.0046551+00:00","Next":"2026-08-07T13:40:00+00:00","LastUpdated":"2026-08-07T13:35:00.0046551+00:00"}
2026-08-07T13:40:00.221 [Information] CosmosClient retry config: MaxAttempts=9 MaxWait=60s
2026-08-07T13:40:00.223 [Warning] CosmosClient initializing with connection string (local development mode), serializer=camelCase
2026-08-07T13:40:00.474 [Information] RetryFailedPayments tick at 08/07/2026 13:40:00. Next: 08/07/2026 13:40:00
2026-08-07T13:40:10.873 [Information] DLQ empty — no payments to retry.
2026-08-07T13:40:10.893 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=4d4dd283-7ca4-42e1-981e-8d90a1304030, Duration=10891ms)
2026-08-07T13:44:59.998 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T13:44:59.9955358+00:00', Id=194eb84c-55ef-4466-b017-dfcfb39d4207)
2026-08-07T13:44:59.998 [Information] Trigger Details: ScheduleStatus: {"Last":"2026-08-07T13:40:00+00:00","Next":"2026-08-07T13:45:00+00:00","LastUpdated":"2026-08-07T13:40:00+00:00"}
2026-08-07T13:45:00.004 [Information] RetryFailedPayments tick at 08/07/2026 13:45:00. Next: 08/07/2026 13:45:00
2026-08-07T13:45:10.067 [Information] DLQ empty — no payments to retry.
2026-08-07T13:45:10.070 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=194eb84c-55ef-4466-b017-dfcfb39d4207, Duration=10075ms)
2026-08-07T15:04:58.686 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 5685319,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:04:59.999 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T15:04:59.9995420+00:00', Id=18705b57-e3e3-42d1-97a0-bdf0e76aff1a)
2026-08-07T15:05:00.000 [Information] Trigger Details: ScheduleStatus: {"Last":"2026-08-07T15:00:00+00:00","Next":"2026-08-07T15:05:00+00:00","LastUpdated":"2026-08-07T15:00:00+00:00"}
2026-08-07T15:05:00.001 [Information] RetryFailedPayments tick at 08/07/2026 15:05:00. Next: 08/07/2026 15:05:00
2026-08-07T15:05:04.298 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 5690931,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:05:10.043 [Information] DLQ empty — no payments to retry.
2026-08-07T15:05:10.046 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=18705b57-e3e3-42d1-97a0-bdf0e76aff1a, Duration=10047ms)
2026-08-07T15:08:08.106 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 5874739,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:08:08.162 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 5874795,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:08:08.627 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 5875260,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:09:59.993 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T15:09:59.9927355+00:00', Id=bfcef14d-7eac-4017-a07a-8e6a57ea9691)
2026-08-07T15:09:59.993 [Information] Trigger Details: ScheduleStatus: {"Last":"2026-08-07T15:05:00+00:00","Next":"2026-08-07T15:10:00+00:00","LastUpdated":"2026-08-07T15:05:00+00:00"}
2026-08-07T15:09:59.994 [Information] RetryFailedPayments tick at 08/07/2026 15:09:59. Next: 08/07/2026 15:10:00
2026-08-07T15:10:10.029 [Information] DLQ empty — no payments to retry.
2026-08-07T15:10:10.031 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=bfcef14d-7eac-4017-a07a-8e6a57ea9691, Duration=10038ms)
2026-08-07T15:11:59.025 [Information] File change of type 'Changed' detected for 'C:\home\site\wwwroot\app_offline.htm'
2026-08-07T15:11:59.025 [Information] Host configuration has changed. Signaling shutdown
2026-08-07T15:11:59.032 [Information] File change of type 'Changed' detected for 'C:\home\site\wwwroot\app_offline.htm'
2026-08-07T15:11:59.032 [Information] Host configuration has changed. Signaling restart
2026-08-07T15:11:59.038 [Information] File change of type 'Changed' detected for 'C:\home\site\wwwroot\app_offline.htm'
2026-08-07T15:11:59.038 [Information] Host configuration has changed. Signaling shutdown
2026-08-07T15:11:59.039 [Information] File change of type 'Changed' detected for 'C:\home\site\wwwroot\app_offline.htm'
2026-08-07T15:11:59.039 [Information] Host configuration has changed. Signaling restart
2026-08-07T15:11:59.095 [Information] Stopping JobHost
2026-08-07T15:11:59.101 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandlePaymentOutcome'
2026-08-07T15:11:59.171 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayRetry'
2026-08-07T15:11:59.178 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayWebhook'
2026-08-07T15:11:59.185 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'ProcessPayment'
2026-08-07T15:11:59.192 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.Host.Listeners.SingletonListener' for function 'RetryFailedPayments'
2026-08-07T15:11:59.218 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'ProcessPayment'
2026-08-07T15:11:59.218 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayWebhook'
2026-08-07T15:11:59.218 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayRetry'
2026-08-07T15:11:59.218 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandlePaymentOutcome'
2026-08-07T15:11:59.230 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.Host.Listeners.SingletonListener' for function 'RetryFailedPayments'
2026-08-07T15:11:59.234 [Information] Job host stopped
2026-08-07T15:12:14.218 [Information] Host lock lease acquired by instance ID '31e6fd1e6b5310b6b2b5f7a59398990c'.
2026-08-07T15:12:20.140 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 19410,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:12:20.147 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 19421,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:12:20.923 [Information] HttpOptions
{
  "DynamicThrottlesEnabled": false,
  "EnableChunkedRequestBinding": false,
  "MaxConcurrentRequests": -1,
  "MaxOutstandingRequests": -1,
  "RoutePrefix": "api"
}
2026-08-07T15:12:20.923 [Information] ServiceBusOptions
{
  "ClientRetryOptions": {
    "Mode": "Exponential",
    "TryTimeout": "00:01:00",
    "Delay": "00:00:00.8000000",
    "MaxDelay": "00:01:00",
    "MaxRetries": 3
  },
  "TransportType": "AmqpTcp",
  "WebProxy": "",
  "AutoCompleteMessages": false,
  "PrefetchCount": 0,
  "MaxAutoLockRenewalDuration": "00:05:00",
  "MaxConcurrentCalls": 16,
  "MaxConcurrentSessions": 8,
  "MaxConcurrentCallsPerSession": 1,
  "MaxMessageBatchSize": 10,
  "MinMessageBatchSize": 1,
  "MaxBatchWaitTime": "00:00:30",
  "SessionIdleTimeout": "",
  "EnableCrossEntityTransactions": false
}
2026-08-07T15:12:20.923 [Information] ConcurrencyOptions
{
  "DynamicConcurrencyEnabled": false,
  "MaximumFunctionConcurrency": 500,
  "CPUThreshold": 0.8,
  "SnapshotPersistenceEnabled": true
}
2026-08-07T15:12:20.940 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 20215,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:15:00.023 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T15:15:00.0081439+00:00', Id=7be7891f-ea7a-4539-9eff-b9ecf7014541)
2026-08-07T15:15:00.028 [Information] Trigger Details: ScheduleStatus: {"Last":"2026-08-07T15:10:00+00:00","Next":"2026-08-07T15:15:00+00:00","LastUpdated":"2026-08-07T15:10:00+00:00"}
2026-08-07T15:15:00.289 [Information] CosmosClient retry config: MaxAttempts=9 MaxWait=60s
2026-08-07T15:15:00.290 [Warning] CosmosClient initializing with connection string (local development mode), serializer=camelCase
2026-08-07T15:15:00.391 [Information] RetryFailedPayments tick at 08/07/2026 15:15:00. Next: 08/07/2026 15:15:00
2026-08-07T15:15:10.764 [Information] DLQ empty — no payments to retry.
2026-08-07T15:15:10.784 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=7be7891f-ea7a-4539-9eff-b9ecf7014541, Duration=10771ms)
2026-08-07T15:16:35.642 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 274917,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:16:39.016 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 278291,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:17:09.930 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 309205,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:17:10.802 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 310077,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:17:19.249 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 318524,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:19:59.996 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T15:19:59.9941745+00:00', Id=26ace331-ad68-4bf2-8153-64e8373b607f)
2026-08-07T15:19:59.997 [Information] Trigger Details: ScheduleStatus: {"Last":"2026-08-07T15:15:00.0042095+00:00","Next":"2026-08-07T15:20:00+00:00","LastUpdated":"2026-08-07T15:15:00.0042095+00:00"}
2026-08-07T15:20:00.002 [Information] RetryFailedPayments tick at 08/07/2026 15:20:00. Next: 08/07/2026 15:20:00
2026-08-07T15:20:09.427 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 488702,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:20:10.011 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 489286,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:20:10.047 [Information] DLQ empty — no payments to retry.
2026-08-07T15:20:10.049 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=26ace331-ad68-4bf2-8153-64e8373b607f, Duration=10055ms)
2026-08-07T15:20:13.277 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 492552,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:22:28.078 [Information] Stopping JobHost
2026-08-07T15:22:28.081 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandlePaymentOutcome'
2026-08-07T15:22:28.106 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayRetry'
2026-08-07T15:22:28.113 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayWebhook'
2026-08-07T15:22:28.120 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'ProcessPayment'
2026-08-07T15:22:28.132 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.Host.Listeners.SingletonListener' for function 'RetryFailedPayments'
2026-08-07T15:22:28.156 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'ProcessPayment'
2026-08-07T15:22:28.157 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayWebhook'
2026-08-07T15:22:28.157 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayRetry'
2026-08-07T15:22:28.157 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandlePaymentOutcome'
2026-08-07T15:22:28.164 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.Host.Listeners.SingletonListener' for function 'RetryFailedPayments'
2026-08-07T15:22:28.168 [Information] Job host stopped
2026-08-07T15:22:47.385 [Information] Host lock lease acquired by instance ID '31e6fd1e6b5310b6b2b5f7a59398990c'.
2026-08-07T15:23:13.006 [Information] HttpOptions
{
  "DynamicThrottlesEnabled": false,
  "EnableChunkedRequestBinding": false,
  "MaxConcurrentRequests": -1,
  "MaxOutstandingRequests": -1,
  "RoutePrefix": "api"
}
2026-08-07T15:23:13.008 [Information] ServiceBusOptions
{
  "ClientRetryOptions": {
    "Mode": "Exponential",
    "TryTimeout": "00:01:00",
    "Delay": "00:00:00.8000000",
    "MaxDelay": "00:01:00",
    "MaxRetries": 3
  },
  "TransportType": "AmqpTcp",
  "WebProxy": "",
  "AutoCompleteMessages": false,
  "PrefetchCount": 0,
  "MaxAutoLockRenewalDuration": "00:05:00",
  "MaxConcurrentCalls": 16,
  "MaxConcurrentSessions": 8,
  "MaxConcurrentCallsPerSession": 1,
  "MaxMessageBatchSize": 10,
  "MinMessageBatchSize": 1,
  "MaxBatchWaitTime": "00:00:30",
  "SessionIdleTimeout": "",
  "EnableCrossEntityTransactions": false
}
2026-08-07T15:23:13.008 [Information] ConcurrencyOptions
{
  "DynamicConcurrencyEnabled": false,
  "MaximumFunctionConcurrency": 500,
  "CPUThreshold": 0.8,
  "SnapshotPersistenceEnabled": true
}
2026-08-07T15:25:00.009 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T15:24:59.9935543+00:00', Id=9e83d162-c009-4e16-b6f9-6746bd9e085f)
2026-08-07T15:25:00.013 [Information] Trigger Details: ScheduleStatus: {"Last":"2026-08-07T15:20:00+00:00","Next":"2026-08-07T15:25:00+00:00","LastUpdated":"2026-08-07T15:20:00+00:00"}
2026-08-07T15:25:00.372 [Information] CosmosClient retry config: MaxAttempts=9 MaxWait=60s
2026-08-07T15:25:00.372 [Warning] CosmosClient initializing with connection string (local development mode), serializer=camelCase
2026-08-07T15:25:00.373 [Information] RetryFailedPayments tick at 08/07/2026 15:25:00. Next: 08/07/2026 15:25:00
2026-08-07T15:25:10.748 [Information] DLQ empty — no payments to retry.
2026-08-07T15:25:10.768 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=9e83d162-c009-4e16-b6f9-6746bd9e085f, Duration=10770ms)
2026-08-07T15:25:22.998 [Information] Stopping JobHost
2026-08-07T15:25:23.000 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandlePaymentOutcome'
2026-08-07T15:25:23.025 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayRetry'
2026-08-07T15:25:23.033 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayWebhook'
2026-08-07T15:25:23.040 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'ProcessPayment'
2026-08-07T15:25:23.047 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.Host.Listeners.SingletonListener' for function 'RetryFailedPayments'
2026-08-07T15:25:23.070 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'ProcessPayment'
2026-08-07T15:25:23.070 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayWebhook'
2026-08-07T15:25:23.070 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayRetry'
2026-08-07T15:25:23.070 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandlePaymentOutcome'
2026-08-07T15:25:23.078 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.Host.Listeners.SingletonListener' for function 'RetryFailedPayments'
2026-08-07T15:25:23.084 [Information] Job host stopped
2026-08-07T15:25:32.382 [Information] Host lock lease acquired by instance ID '31e6fd1e6b5310b6b2b5f7a59398990c'.
2026-08-07T15:25:58.172 [Information] HttpOptions
{
  "DynamicThrottlesEnabled": false,
  "EnableChunkedRequestBinding": false,
  "MaxConcurrentRequests": -1,
  "MaxOutstandingRequests": -1,
  "RoutePrefix": "api"
}
2026-08-07T15:25:58.173 [Information] ServiceBusOptions
{
  "ClientRetryOptions": {
    "Mode": "Exponential",
    "TryTimeout": "00:01:00",
    "Delay": "00:00:00.8000000",
    "MaxDelay": "00:01:00",
    "MaxRetries": 3
  },
  "TransportType": "AmqpTcp",
  "WebProxy": "",
  "AutoCompleteMessages": false,
  "PrefetchCount": 0,
  "MaxAutoLockRenewalDuration": "00:05:00",
  "MaxConcurrentCalls": 16,
  "MaxConcurrentSessions": 8,
  "MaxConcurrentCallsPerSession": 1,
  "MaxMessageBatchSize": 10,
  "MinMessageBatchSize": 1,
  "MaxBatchWaitTime": "00:00:30",
  "SessionIdleTimeout": "",
  "EnableCrossEntityTransactions": false
}
2026-08-07T15:25:58.174 [Information] ConcurrencyOptions
{
  "DynamicConcurrencyEnabled": false,
  "MaximumFunctionConcurrency": 500,
  "CPUThreshold": 0.8,
  "SnapshotPersistenceEnabled": true
}
2026-08-07T15:26:37.016 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 74137,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:26:37.162 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 74287,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:26:40.301 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 77425,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:30:00.009 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T15:29:59.9940179+00:00', Id=3fc03170-49af-4c84-937e-9791e2b64e4d)
2026-08-07T15:30:00.014 [Information] Trigger Details: ScheduleStatus: {"Last":"2026-08-07T15:25:00+00:00","Next":"2026-08-07T15:30:00+00:00","LastUpdated":"2026-08-07T15:25:00+00:00"}
2026-08-07T15:30:00.366 [Information] CosmosClient retry config: MaxAttempts=9 MaxWait=60s
2026-08-07T15:30:00.366 [Warning] CosmosClient initializing with connection string (local development mode), serializer=camelCase
2026-08-07T15:30:00.366 [Information] RetryFailedPayments tick at 08/07/2026 15:30:00. Next: 08/07/2026 15:30:00
2026-08-07T15:30:10.763 [Information] DLQ empty — no payments to retry.
2026-08-07T15:30:10.783 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=3fc03170-49af-4c84-937e-9791e2b64e4d, Duration=10785ms)
2026-08-07T15:30:53.232 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 330357,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:31:05.615 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 342740,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:31:05.951 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 343075,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:31:08.036 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 345161,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:31:16.115 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 353240,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:33:27.490 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 484615,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:33:28.135 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 485259,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T15:33:28.702 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "31e6fd1e6b5310b6b2b5f7a59398990cb40df34c9815b6e96ca4ce11be784006",
  "computerName": "wn1xsdwk000P4S",
  "processUptime": 485827,
  "functionAppContentEditingState": "Unknown"
}
