using System.Diagnostics.CodeAnalysis;
using Azure.Identity;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using PaymentServices.AccountResolution.Models;
using PaymentServices.AccountResolution.Repositories;
using PaymentServices.AccountResolution.Services;
using PaymentServices.Shared.Extensions;
using Serilog;
using Serilog.Events;
using StackExchange.Redis;
using CosmosContainer = Microsoft.Azure.Cosmos.Container;

namespace PaymentServices.AccountResolution;

[ExcludeFromCodeCoverage]
public static class Program
{
    private const string Prefix = "accountResolution:AppSettings";

    public static async Task Main(string[] args)
    {
        var host = new HostBuilder()
            .ConfigureAppConfiguration(SetupAppConfiguration)
            .ConfigureFunctionsWebApplication()
            .ConfigureServices((context, services) =>
            {
                var config = context.Configuration;

                SetupSerilog(config);

                // Application Insights
                services.AddApplicationInsightsTelemetryWorkerService();
                services.ConfigureFunctionsApplicationInsights();

                // Shared infrastructure
                services.AddPaymentAppSettings(config, Prefix);
                services.AddPaymentCosmosClient(config, Prefix);
                services.AddPaymentServiceBusPublisher(config, Prefix);

                // AccountResolution-specific settings
                services.AddOptions<AccountResolutionSettings>()
                    .Configure<IConfiguration>((settings, cfg) =>
                        cfg.GetSection(Prefix).Bind(settings));

                // Cosmos containers
                RegisterCosmosContainers(services, config);

                // Repositories
                services.AddTransient<IAccountRepository, AccountRepository>();
                services.AddTransient<ITransactionStateRepository, TransactionStateRepository>();
                services.AddTransient<IOnboardRepository, OnboardRepository>();

                // Redis cache — singleton connection, silent fallback if unavailable
                var redisConnString = config[$"{Prefix}:REDIS_CONNSTRING"] ?? string.Empty;
                if (!string.IsNullOrWhiteSpace(redisConnString))
                {
                    services.AddSingleton<IConnectionMultiplexer>(_ =>
                        ConnectionMultiplexer.Connect(redisConnString));
                    services.AddSingleton<ICacheService, RedisCacheService>();
                }
                else
                {
                    services.AddSingleton<ICacheService, NoOpCacheService>();
                }

                // Services
                services.AddTransient<IAccountResolutionService, AccountResolutionService>();
                services.AddTransient<IOnboardService, OnboardService>();

                services.AddHttpClient();
                services.AddHealthChecks();
            })
            .ConfigureLogging((context, logging) =>
            {
                logging.Services.Configure<LoggerFilterOptions>(options =>
                {
                    var defaultRule = options.Rules.FirstOrDefault(rule =>
                        rule.ProviderName ==
                        "Microsoft.Extensions.Logging.ApplicationInsights.ApplicationInsightsLoggerProvider");

                    if (defaultRule is not null)
                        options.Rules.Remove(defaultRule);
                });

                logging.AddSerilog(dispose: true);
            })
            .Build();

        await host.RunAsync();
    }

    private static void SetupAppConfiguration(IConfigurationBuilder builder)
    {
        builder.AddEnvironmentVariables();
        var settings = builder.Build();

        var appConfigUrl = settings["AppConfig:Endpoint"];
        var azureClientId = settings["AZURE_CLIENT_ID"];

        if (!string.IsNullOrWhiteSpace(appConfigUrl) && !string.IsNullOrWhiteSpace(azureClientId))
        {
            var credentialOptions = new DefaultAzureCredentialOptions
            {
                ManagedIdentityClientId = azureClientId
            };
            var credential = new DefaultAzureCredential(credentialOptions);

            builder.AddAzureAppConfiguration(options =>
            {
                options
                    .Connect(new Uri(appConfigUrl), credential)
                    .Select("accountResolution:*")
                    .Select("telemetry:*")
                    .ConfigureKeyVault(kv => kv.SetCredential(credential));
            });
        }

        builder
            .SetBasePath(Environment.CurrentDirectory)
            .AddJsonFile("local.settings.json", optional: true, reloadOnChange: false);
    }

    private static void SetupSerilog(IConfiguration config)
    {
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Information()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
            .MinimumLevel.Override("Microsoft.Azure.Functions.Worker", LogEventLevel.Warning)
            .MinimumLevel.Override("Host", LogEventLevel.Warning)
            .Enrich.FromLogContext()
            .Enrich.WithProperty("Service", "PaymentServices.AccountResolution")
            .Enrich.WithProperty("Environment",
                Environment.GetEnvironmentVariable("AZURE_FUNCTIONS_ENVIRONMENT") ?? "Production")
            .CreateLogger();
    }

    private static void RegisterCosmosContainers(IServiceCollection services, IConfiguration config)
    {
        var database = config[$"{Prefix}:COSMOS_DATABASE"] ?? "tptch";

        services.AddKeyedSingleton<CosmosContainer>("accounts", (sp, _) =>
        {
            var client = sp.GetRequiredService<CosmosClient>();
            var container = config[$"{Prefix}:COSMOS_ACCOUNTS_CONTAINER"] ?? "accounts";
            return client.GetContainer(database, container);
        });

        services.AddKeyedSingleton<CosmosContainer>("remoteAccounts", (sp, _) =>
        {
            var client = sp.GetRequiredService<CosmosClient>();
            var container = config[$"{Prefix}:COSMOS_REMOTE_ACCOUNTS_CONTAINER"] ?? "remoteAccounts";
            return client.GetContainer(database, container);
        });

        services.AddKeyedSingleton<CosmosContainer>("customers", (sp, _) =>
        {
            var client = sp.GetRequiredService<CosmosClient>();
            var container = config[$"{Prefix}:COSMOS_CUSTOMERS_CONTAINER"] ?? "customers";
            return client.GetContainer(database, container);
        });

        services.AddKeyedSingleton<CosmosContainer>("platforms", (sp, _) =>
        {
            var client = sp.GetRequiredService<CosmosClient>();
            var container = config[$"{Prefix}:COSMOS_PLATFORMS_CONTAINER"] ?? "platforms";
            return client.GetContainer(database, container);
        });

        services.AddKeyedSingleton<CosmosContainer>("transactions", (sp, _) =>
        {
            var client = sp.GetRequiredService<CosmosClient>();
            var container = config[$"{Prefix}:COSMOS_TRANSACTIONS_CONTAINER"] ?? "tchSendTransactions";
            return client.GetContainer(database, container);
        });

        services.AddKeyedSingleton<CosmosContainer>("ledgers", (sp, _) =>
        {
            var client = sp.GetRequiredService<CosmosClient>();
            var ledgerDb = config[$"{Prefix}:COSMOS_LEDGER_DATABASE"] ?? "ledgers";
            var ledgerContainer = config[$"{Prefix}:COSMOS_LEDGER_CONTAINER"] ?? "ledgers";
            return client.GetContainer(ledgerDb, ledgerContainer);
        });
    }
}
