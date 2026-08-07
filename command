2026-08-07T03:51:00.180 [Information] Host lock lease acquired by instance ID '8a9d121c9d8fb192f53a889bf2512ef0'.
2026-08-07T03:51:16.813 [Information] File change of type 'Changed' detected for 'C:\home\site\wwwroot\app_offline.htm'
2026-08-07T03:51:16.815 [Information] Host configuration has changed. Signaling shutdown
2026-08-07T03:51:16.818 [Information] File change of type 'Changed' detected for 'C:\home\site\wwwroot\app_offline.htm'
2026-08-07T03:51:16.818 [Information] Host configuration has changed. Signaling restart
2026-08-07T03:51:16.832 [Information] File change of type 'Changed' detected for 'C:\home\site\wwwroot\app_offline.htm'
2026-08-07T03:51:16.832 [Information] Host configuration has changed. Signaling shutdown
2026-08-07T03:51:16.832 [Information] File change of type 'Changed' detected for 'C:\home\site\wwwroot\app_offline.htm'
2026-08-07T03:51:16.832 [Information] Host configuration has changed. Signaling restart
2026-08-07T03:51:16.861 [Information] Stopping JobHost
2026-08-07T03:51:16.867 [Information] Job host stopped
2026-08-07T03:51:31.903 [Warning] [Tag=''] Process reporting unhealthy: Unhealthy. Health check entries are {"azure.functions.web_host.lifecycle":{"status":"Healthy","description":null},"azure.functions.script_host.lifecycle":{"status":"Unhealthy","description":"No script host available","errorCode":"NoScriptHost"},"azure.functions.webjobs.storage":{"status":"Healthy","description":null}}
2026-08-07T03:51:31.910 [Warning] [Tag='azure.functions.readiness'] Process reporting unhealthy: Unhealthy. Health check entries are {"azure.functions.script_host.lifecycle":{"status":"Unhealthy","description":"No script host available","errorCode":"NoScriptHost"}}
2026-08-07T03:51:33.193 [Error] Exceeded language worker restart retry count for runtime:dotnet-isolated. Shutting down and proactively recycling the Functions Host to recover
2026-08-07T03:51:33.214 [Information] Reading functions metadata (Custom)
2026-08-07T03:51:33.231 [Information] 0 functions found (Custom)
2026-08-07T03:51:33.245 [Information] 0 functions loaded
2026-08-07T03:51:33.248 [Error] Unhandled exception. Grpc.Core.RpcException: Status(StatusCode="Unavailable", Detail="Error connecting to subchannel.", DebugException="System.Net.Sockets.SocketException: An attempt was made to access a socket in a way forbidden by its access permissions.")
2026-08-07T03:51:33.248 [Information] ---> System.Net.Sockets.SocketException (10013): An attempt was made to access a socket in a way forbidden by its access permissions.
2026-08-07T03:51:33.248 [Error] at System.Net.Sockets.Socket.AwaitableSocketAsyncEventArgs.ThrowException(SocketError error, CancellationToken cancellationToken)
2026-08-07T03:51:33.248 [Information] at System.Net.Sockets.Socket.AwaitableSocketAsyncEventArgs.System.Threading.Tasks.Sources.IValueTaskSource.GetResult(Int16 token)
2026-08-07T03:51:33.248 [Information] at Grpc.Net.Client.Balancer.Internal.SocketConnectivitySubchannelTransport.TryConnectAsync(ConnectContext context, Int32 attempt)
2026-08-07T03:51:33.248 [Information] --- End of inner exception stack trace ---
2026-08-07T03:51:33.248 [Information] at Grpc.Net.Client.Internal.HttpContentClientStreamWriter`2.WriteAsyncCore[TState](Func`5 writeFunc, TState state, CancellationToken cancellationToken)
2026-08-07T03:51:33.248 [Information] at Grpc.Net.Client.Internal.HttpContentClientStreamWriter`2.WriteCoreAsync(TRequest message, CancellationToken cancellationToken)
2026-08-07T03:51:33.248 [Information] at Microsoft.Azure.Functions.Worker.Grpc.GrpcWorkerClientFactory.GrpcWorkerClient.SendStartStreamMessageAsync(IClientStreamWriter`1 requestStream) in /_/src/DotNetWorker.Grpc/GrpcWorkerClientFactory.cs:line 84
2026-08-07T03:51:33.248 [Information] at Microsoft.Azure.Functions.Worker.Grpc.GrpcWorkerClientFactory.GrpcWorkerClient.StartAsync(CancellationToken token) in /_/src/DotNetWorker.Grpc/GrpcWorkerClientFactory.cs:line 66
2026-08-07T03:51:33.248 [Information] at Microsoft.Azure.Functions.Worker.WorkerHostedService.StartAsync(CancellationToken cancellationToken) in /_/src/DotNetWorker.Core/WorkerHostedService.cs:line 25
2026-08-07T03:51:33.248 [Information] at Microsoft.Extensions.Hosting.Internal.Host.<StartAsync>b__14_1(IHostedService service, CancellationToken token)
2026-08-07T03:51:33.248 [Information] at Microsoft.Extensions.Hosting.Internal.Host.ForeachService[T](IEnumerable`1 services, CancellationToken token, Boolean concurrent, Boolean abortOnFirstException, List`1 exceptions, Func`3 operation)
2026-08-07T03:51:33.248 [Information] at Microsoft.Extensions.Hosting.Internal.Host.StartAsync(CancellationToken cancellationToken)
2026-08-07T03:51:33.248 [Information] at Microsoft.Extensions.Hosting.HostingAbstractionsHostExtensions.RunAsync(IHost host, CancellationToken token)
2026-08-07T03:51:33.248 [Information] at Microsoft.Extensions.Hosting.HostingAbstractionsHostExtensions.RunAsync(IHost host, CancellationToken token)
2026-08-07T03:51:33.249 [Information] at PaymentServices.RTPSend.Program.Main(String[] args) in /home/vsts/work/1/s/src/Program.cs:line 179
2026-08-07T03:51:33.249 [Information] at PaymentServices.RTPSend.Program.<Main>(String[] args)
2026-08-07T03:51:33.249 [Information] ScriptJobHostOptions
{
  "FileWatchingEnabled": true,
  "FileLoggingMode": "DebugOnly",
  "FunctionTimeout": "00:30:00",
  "TelemetryMode": "ApplicationInsights"
}
2026-08-07T03:51:33.249 [Information] ApplicationInsightsLoggerOptions
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
2026-08-07T03:51:33.249 [Information] LoggerFilterOptions
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
2026-08-07T03:51:33.249 [Information] HttpWorkerOptions
{
  "Type": 0,
  "Description": null,
  "Arguments": null,
  "Port": 50308,
  "IsPortManuallySet": false,
  "EnableForwardingHttpRequest": false,
  "EnableProxyingHttpRequest": false,
  "InitializationTimeout": "00:00:30",
  "CustomRoutesEnabled": false,
  "Http": null
}
2026-08-07T03:51:33.249 [Information] ScriptJobHostOptions
{
  "FileWatchingEnabled": true,
  "FileLoggingMode": "DebugOnly",
  "FunctionTimeout": "00:30:00",
  "TelemetryMode": "ApplicationInsights"
}
2026-08-07T03:51:33.249 [Information] FunctionResultAggregatorOptions
{
  "BatchSize": 1000,
  "FlushTimeout": "00:00:30",
  "IsEnabled": true
}
2026-08-07T03:51:33.249 [Information] ConcurrencyOptions
{
  "DynamicConcurrencyEnabled": false,
  "MaximumFunctionConcurrency": 500,
  "CPUThreshold": 0.8,
  "SnapshotPersistenceEnabled": true
}
2026-08-07T03:51:33.249 [Information] ServiceBusOptions
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
2026-08-07T03:51:33.249 [Information] SingletonOptions
{
  "LockPeriod": "00:00:15",
  "ListenerLockPeriod": "00:01:00",
  "LockAcquisitionTimeout": "10675199.02:48:05.4775807",
  "LockAcquisitionPollingInterval": "00:00:05",
  "ListenerLockRecoveryPollingInterval": "00:01:00"
}
2026-08-07T03:51:33.249 [Information] TimerTriggerPlatformOptions
{
  "NonCronScheduleBehavior": "Allow"
}
2026-08-07T03:51:33.249 [Information] ScaleOptions
{
  "ScaleMetricsMaxAge": "00:02:00",
  "ScaleMetricsSampleInterval": "00:00:10",
  "MetricsPurgeEnabled": true,
  "IsTargetScalingEnabled": true,
  "IsRuntimeScalingEnabled": false
}
2026-08-07T03:51:33.249 [Information] Starting JobHost
2026-08-07T03:51:33.250 [Information] Starting Host (HostId=fa-pmtsvc-rtpsend-prod-eastus, InstanceId=8745445b-efef-424b-b68b-ee274226cb61, Version=4.1052.300.26370, ProcessId=6656, AppDomainId=1, InDebugMode=True, InDiagnosticMode=False, FunctionsExtensionVersion=~4)
2026-08-07T03:51:33.253 [Information] Loading functions metadata
2026-08-07T03:51:33.263 [Information] Stopping JobHost
2026-08-07T03:51:35.041 [Error] Unhandled exception. Grpc.Core.RpcException: Status(StatusCode="Unavailable", Detail="Error connecting to subchannel.", DebugException="System.Net.Sockets.SocketException: An attempt was made to access a socket in a way forbidden by its access permissions.")
2026-08-07T03:51:35.041 [Information] ---> System.Net.Sockets.SocketException (10013): An attempt was made to access a socket in a way forbidden by its access permissions.
2026-08-07T03:51:35.041 [Error] at System.Net.Sockets.Socket.AwaitableSocketAsyncEventArgs.ThrowException(SocketError error, CancellationToken cancellationToken)
2026-08-07T03:51:35.041 [Information] at System.Net.Sockets.Socket.AwaitableSocketAsyncEventArgs.System.Threading.Tasks.Sources.IValueTaskSource.GetResult(Int16 token)
2026-08-07T03:51:35.041 [Information] at Grpc.Net.Client.Balancer.Internal.SocketConnectivitySubchannelTransport.TryConnectAsync(ConnectContext context, Int32 attempt)
2026-08-07T03:51:35.041 [Information] --- End of inner exception stack trace ---
2026-08-07T03:51:35.041 [Information] at Grpc.Net.Client.Internal.HttpContentClientStreamWriter`2.WriteAsyncCore[TState](Func`5 writeFunc, TState state, CancellationToken cancellationToken)
2026-08-07T03:51:35.041 [Information] at Grpc.Net.Client.Internal.HttpContentClientStreamWriter`2.WriteCoreAsync(TRequest message, CancellationToken cancellationToken)
2026-08-07T03:51:35.041 [Information] at Microsoft.Azure.Functions.Worker.Grpc.GrpcWorkerClientFactory.GrpcWorkerClient.SendStartStreamMessageAsync(IClientStreamWriter`1 requestStream) in /_/src/DotNetWorker.Grpc/GrpcWorkerClientFactory.cs:line 84
2026-08-07T03:51:35.041 [Information] at Microsoft.Azure.Functions.Worker.Grpc.GrpcWorkerClientFactory.GrpcWorkerClient.StartAsync(CancellationToken token) in /_/src/DotNetWorker.Grpc/GrpcWorkerClientFactory.cs:line 66
2026-08-07T03:51:35.041 [Information] at Microsoft.Azure.Functions.Worker.WorkerHostedService.StartAsync(CancellationToken cancellationToken) in /_/src/DotNetWorker.Core/WorkerHostedService.cs:line 25
2026-08-07T03:51:35.041 [Information] at Microsoft.Extensions.Hosting.Internal.Host.<StartAsync>b__14_1(IHostedService service, CancellationToken token)
2026-08-07T03:51:35.041 [Information] at Microsoft.Extensions.Hosting.Internal.Host.ForeachService[T](IEnumerable`1 services, CancellationToken token, Boolean concurrent, Boolean abortOnFirstException, List`1 exceptions, Func`3 operation)
2026-08-07T03:51:35.041 [Information] at Microsoft.Extensions.Hosting.Internal.Host.StartAsync(CancellationToken cancellationToken)
2026-08-07T03:51:35.041 [Information] at Microsoft.Extensions.Hosting.HostingAbstractionsHostExtensions.RunAsync(IHost host, CancellationToken token)
2026-08-07T03:51:35.041 [Information] at Microsoft.Extensions.Hosting.HostingAbstractionsHostExtensions.RunAsync(IHost host, CancellationToken token)
2026-08-07T03:51:35.041 [Information] at PaymentServices.RTPSend.Program.Main(String[] args) in /home/vsts/work/1/s/src/Program.cs:line 179
2026-08-07T03:51:35.041 [Information] at PaymentServices.RTPSend.Program.<Main>(String[] args)
2026-08-07T03:51:35.098 [Error] Exceeded language worker restart retry count for runtime:dotnet-isolated. Shutting down and proactively recycling the Functions Host to recover
2026-08-07T03:51:35.098 [Information] 0 functions loaded
2026-08-07T03:51:38.301 [Information] Host lock lease acquired by instance ID '8a9d121c9d8fb192f53a889bf2512ef0'.
2026-08-07T03:52:00.739 [Information] Host lock lease acquired by instance ID '8a9d121c9d8fb192f53a889bf2512ef0'.
2026-08-07T03:52:14.848 [Information] Stopping JobHost
2026-08-07T03:52:14.852 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandlePaymentOutcome'
2026-08-07T03:52:14.929 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayRetry'
2026-08-07T03:52:14.938 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayWebhook'
2026-08-07T03:52:14.946 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'ProcessPayment'
2026-08-07T03:52:14.983 [Information] Stopping the listener 'Microsoft.Azure.WebJobs.Host.Listeners.SingletonListener' for function 'RetryFailedPayments'
2026-08-07T03:52:15.007 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'ProcessPayment'
2026-08-07T03:52:15.007 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayWebhook'
2026-08-07T03:52:15.007 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandleTabaPayRetry'
2026-08-07T03:52:15.007 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.ServiceBus.Listeners.ServiceBusListener' for function 'HandlePaymentOutcome'
2026-08-07T03:52:15.015 [Information] Stopped the listener 'Microsoft.Azure.WebJobs.Host.Listeners.SingletonListener' for function 'RetryFailedPayments'
2026-08-07T03:52:15.019 [Information] Job host stopped
2026-08-07T03:52:25.587 [Information] Host lock lease acquired by instance ID '8a9d121c9d8fb192f53a889bf2512ef0'.
2026-08-07T03:52:30.785 [Information] HttpOptions
{
  "DynamicThrottlesEnabled": false,
  "EnableChunkedRequestBinding": false,
  "MaxConcurrentRequests": -1,
  "MaxOutstandingRequests": -1,
  "RoutePrefix": "api"
}
2026-08-07T03:52:30.786 [Information] ServiceBusOptions
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
2026-08-07T03:52:30.786 [Information] ConcurrencyOptions
{
  "DynamicConcurrencyEnabled": false,
  "MaximumFunctionConcurrency": 500,
  "CPUThreshold": 0.8,
  "SnapshotPersistenceEnabled": true
}
2026-08-07T03:53:55.714 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 100980,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:53:55.831 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 101098,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:54:38.242 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 143509,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:54:38.274 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 143541,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:54:39.815 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 145082,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:55:00.024 [Information] Executing 'Functions.RetryFailedPayments' (Reason='Timer fired at 2026-08-07T03:55:00.0090543+00:00', Id=b1ae48d4-0f44-4576-af64-25852ee91951)
2026-08-07T03:55:00.029 [Information] Trigger Details: ScheduleStatus: {"Last":"0001-01-01T00:00:00+00:00","Next":"2026-08-07T03:55:00+00:00","LastUpdated":"2026-08-07T03:51:56.5094963+00:00"}
2026-08-07T03:55:00.196 [Information] CosmosClient retry config: MaxAttempts=9 MaxWait=60s
2026-08-07T03:55:00.197 [Warning] CosmosClient initializing with connection string (local development mode), serializer=camelCase
2026-08-07T03:55:00.567 [Information] RetryFailedPayments tick at 08/07/2026 03:55:00. Next: 08/07/2026 03:55:00
2026-08-07T03:55:10.855 [Information] DLQ empty — no payments to retry.
2026-08-07T03:55:10.875 [Information] Executed 'Functions.RetryFailedPayments' (Succeeded, Id=b1ae48d4-0f44-4576-af64-25852ee91951, Duration=10862ms)
2026-08-07T03:56:07.710 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 232977,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:56:07.714 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 232981,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:56:07.758 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 233025,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:56:20.891 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 246158,
  "functionAppContentEditingState": "Unknown"
}
2026-08-07T03:56:23.002 [Information] Host Status: {
  "id": "fa-pmtsvc-rtpsend-prod-eastus",
  "state": "Running",
  "version": "4.1052.300.26370",
  "versionDetails": "4.1052.300+00515b21db39db50346f38f951eceb85fdbd05d4",
  "platformVersion": "109.0.7.36",
  "instanceId": "8a9d121c9d8fb192f53a889bf2512ef0ec1812dd1a73065f145bcc785a851b19",
  "computerName": "wn0xsdwk000NYR",
  "processUptime": 248269,
  "functionAppContentEditingState": "Unknown"
}
