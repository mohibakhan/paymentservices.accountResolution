using System;
using System.Linq;
using Azure.Identity;
using FluentValidation;
using System.Threading.Tasks;
using FluentValidation.AspNetCore;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System.Diagnostics.CodeAnalysis;
using Microsoft.Azure.Functions.Worker;
using ReceivePaymentServicesFA.Helpers;
using ReceivePaymentServicesFA.Settings;
using ReceivePaymentServicesFA.Services;
using ReceivePaymentServicesFA.Interface;
using Microsoft.Extensions.Configuration;
using ReceivePaymentServicesFA.Providers;
using ReceivePaymentServicesFA.Validators;
using ReceivePaymentServicesFA.Repositories;
using Microsoft.Extensions.DependencyInjection;
using ReceivePaymentServicesFA.Services.Facade;
using Evolve.Digital.Azure.ApplicationInsights;
using Microsoft.ApplicationInsights.Extensibility;
using ReceivePaymentServicesFA.Interface.Services;
using ReceivePaymentServicesFA.Interface.Adapters;
using ReceivePaymentServicesFA.Repositories.Adapters;
using ReceivePaymentServicesFA.Interface.CosmosDataAdapter;
using ReceivePaymentServicesFA.Services.Facade.SubSystems;
using Evolve.Digital.Azure.ApplicationInsights.TelemetryInitializers;

/// <summary>
/// Main program class.
/// </summary>
[ExcludeFromCodeCoverage]
public static class Program
{
    /// <summary>
    /// Main entry point for the function app.
    /// </summary>
    /// <param name="args">The application arguments.</param>
    /// <returns>A task.</returns>
    public static Task Main(string[] args)
    {
        var host = new HostBuilder()
            .ConfigureAppConfiguration(SetupAppConfiguration)
            .ConfigureFunctionsWebApplication()
            .ConfigureServices(services =>
            {
                DependencyInjection(services);
                InitializeAppSettings(services);
            })
            .ConfigureLogging(logging =>
            {
                logging.Services.Configure<LoggerFilterOptions>(options =>
                {
                    LoggerFilterRule defaultRule = options.Rules.FirstOrDefault(rule => rule.ProviderName
                        == "Microsoft.Extensions.Logging.ApplicationInsights.ApplicationInsightsLoggerProvider");
                    if (defaultRule is not null)
                    {
                        options.Rules.Remove(defaultRule);
                    }
                });
            })
            .Build();

        return host.RunAsync();
    }

    private static void SetupAppConfiguration(IConfigurationBuilder builder)
    {
        // Need this first to pull the settings from the Function App configuration
        builder.AddEnvironmentVariables();
        var settings = builder.Build();
        var appConfigUrl = settings["AppConfig:Endpoint"];
        var azureClientId = settings["AZURE_CLIENT_ID"];

        if (!string.IsNullOrWhiteSpace(appConfigUrl) && !string.IsNullOrWhiteSpace(azureClientId))
        {
            var credentialOptions = new DefaultAzureCredentialOptions();
            credentialOptions.ManagedIdentityClientId = azureClientId;
            var credential = new DefaultAzureCredential(credentialOptions);

            builder.AddAzureAppConfiguration(options =>
            {
                options.Select("rtpReceive:*");
                options.Select("telemetry:*");
                options.Connect(new Uri(appConfigUrl), credential)
                    .ConfigureKeyVault(kv => { kv.SetCredential(credential); });
            });
        }

        builder
            .SetBasePath(Environment.CurrentDirectory)
            .AddJsonFile("local.settings.json", true, false);
    }
    private static void InitializeAppSettings(IServiceCollection services)
    {
        services.AddOptions<AppSettings>().Configure<IConfiguration>((settings, configuration) =>
        {
            configuration.GetSection("rtpReceive:AppSettings").Bind(settings);
        });

        services.AddOptions<TelemetryAppSettings>().Configure<IConfiguration>((settings, configuration) =>
        {
            configuration.GetSection("telemetry").Bind(settings);
        });
    }
    private static void DependencyInjection(IServiceCollection services)
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        services.AddSingleton<ITelemetryInitializer, HttpTelemetryInitializer>();

        // Add health checks
        services.AddHealthChecks();

        // Inject service dependencies
        services.AddSingleton<IPaymentCosmosDBService, PaymentCosmosDBService>();
        services.AddSingleton<IPartnerLedgerCosmosDBAdapter, PartnerLedgerCosmosDBAdapter>();
        services.AddSingleton<ICounterPartyCosmosDBAdapter, CounterPartyCosmosDBAdapter>();
        services.AddTransient<IJhaService, JhaService>();
        services.AddTransient<IJhaHistoryService, DepositHistoryService>();
        services.AddTransient<ITchStatusService, TchStatusService>();
        services.AddSingleton<IEvolveRequestHelper, EvolveRequestHelper>();
        services.AddTransient<IServiceBusAdapter, ServiceBusAdapter>();
        services.AddTransient<IServiceBusMessageService, ServiceBusMessageService>();
        services.AddTransient<ISendGridEmailService, SendGridEmailService>();
        services.AddSingleton<PartnerLedgerSystem>();
        services.AddSingleton<PrefundLedgerSystem>();
        services.AddSingleton<TransferSystem>();
        services.AddSingleton<CounterPartySystem>();
        services.AddScoped<IPreRtpChecksFacade, PreRtpChecksFacade>();
        services.AddSingleton<IHealthCheckServiceProvider, HealthCheckServiceProvider>();

        services.AddFluentValidationAutoValidation();
        services.AddFluentValidationClientsideAdapters();
        services.AddValidatorsFromAssemblyContaining<TabaPayRequestValidator>();

        // This is necessary for the IHttpClientFactory
        services.AddHttpContextAccessor();
        services.AddHttpClient();
        services.AddLogging();
    }
}