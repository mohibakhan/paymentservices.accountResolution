using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using PaymentServices.AccountResolution.Models;
using PaymentServices.AccountResolution.Services;

namespace PaymentServices.AccountResolution.Functions;

/// <summary>
/// HTTP Triggers for customer and account onboarding.
/// These are pre-flight operations run before a client goes live.
///
/// POST /onboard/customer — creates Customer, links to Platform
/// POST /onboard/account  — creates Account, RemoteAccount, Ledger, links to Customer
/// </summary>
public sealed class OnboardFunction
{
    private readonly IOnboardService _onboardService;
    private readonly ILogger<OnboardFunction> _logger;

    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    public OnboardFunction(
        IOnboardService onboardService,
        ILogger<OnboardFunction> logger)
    {
        _onboardService = onboardService;
        _logger = logger;
    }

    // -------------------------------------------------------------------------
    // POST /onboard/customer
    // -------------------------------------------------------------------------

    [Function(nameof(OnboardCustomer))]
    public async Task<HttpResponseData> OnboardCustomer(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "onboard/customer")]
        HttpRequestData req,
        FunctionContext context,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("OnboardCustomer request received.");

        OnboardCustomerRequest? request;
        try
        {
            request = await JsonSerializer.DeserializeAsync<OnboardCustomerRequest>(
                req.Body, _jsonOptions, cancellationToken);

            if (request is null)
                return await ProblemAsync(req,
                    "Request body is required.", HttpStatusCode.BadRequest, cancellationToken);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning("OnboardCustomer deserialization failed. Error={Error}", ex.Message);
            return await ProblemAsync(req,
                "Invalid JSON payload.", HttpStatusCode.BadRequest, cancellationToken);
        }

        // Basic validation
        if (string.IsNullOrWhiteSpace(request.FintechId))
            return await ProblemAsync(req,
                "fintechId is required.", HttpStatusCode.BadRequest, cancellationToken);

        if (request.Name is null ||
            (!request.Name.IsBusiness &&
             (string.IsNullOrWhiteSpace(request.Name.First) ||
              string.IsNullOrWhiteSpace(request.Name.Last))))
            return await ProblemAsync(req,
                "name must have either first+last or company.",
                HttpStatusCode.BadRequest, cancellationToken);

        try
        {
            var result = await _onboardService.OnboardCustomerAsync(request, cancellationToken);

            var response = req.CreateResponse(HttpStatusCode.Created);
            response.Headers.Add("Content-Type", "application/json");
            await response.WriteStringAsync(
                JsonSerializer.Serialize(result, _jsonOptions), cancellationToken);

            _logger.LogInformation(
                "Customer onboarded successfully. CustomerId={CustomerId}", result.CustomerId);

            return response;
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogWarning("OnboardCustomer failed. Error={Error}", ex.Message);
            return await ProblemAsync(req, ex.Message, HttpStatusCode.BadRequest, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "OnboardCustomer unexpected error.");
            return await ProblemAsync(req,
                "An unexpected error occurred.", HttpStatusCode.InternalServerError, cancellationToken);
        }
    }

    // -------------------------------------------------------------------------
    // POST /onboard/account
    // -------------------------------------------------------------------------

    [Function(nameof(OnboardAccount))]
    public async Task<HttpResponseData> OnboardAccount(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "onboard/account")]
        HttpRequestData req,
        FunctionContext context,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("OnboardAccount request received.");

        OnboardAccountRequest? request;
        try
        {
            request = await JsonSerializer.DeserializeAsync<OnboardAccountRequest>(
                req.Body, _jsonOptions, cancellationToken);

            if (request is null)
                return await ProblemAsync(req,
                    "Request body is required.", HttpStatusCode.BadRequest, cancellationToken);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning("OnboardAccount deserialization failed. Error={Error}", ex.Message);
            return await ProblemAsync(req,
                "Invalid JSON payload.", HttpStatusCode.BadRequest, cancellationToken);
        }

        // Basic validation
        if (string.IsNullOrWhiteSpace(request.CustomerId))
            return await ProblemAsync(req,
                "customerId is required.", HttpStatusCode.BadRequest, cancellationToken);

        if (string.IsNullOrWhiteSpace(request.AccountNumber))
            return await ProblemAsync(req,
                "accountNumber is required.", HttpStatusCode.BadRequest, cancellationToken);

        if (string.IsNullOrWhiteSpace(request.RoutingNumber) || request.RoutingNumber.Length != 9)
            return await ProblemAsync(req,
                "routingNumber must be 9 digits.", HttpStatusCode.BadRequest, cancellationToken);

        if (string.IsNullOrWhiteSpace(request.FintechId))
            return await ProblemAsync(req,
                "fintechId is required.", HttpStatusCode.BadRequest, cancellationToken);

        try
        {
            var result = await _onboardService.OnboardAccountAsync(request, cancellationToken);

            var response = req.CreateResponse(HttpStatusCode.Created);
            response.Headers.Add("Content-Type", "application/json");
            await response.WriteStringAsync(
                JsonSerializer.Serialize(result, _jsonOptions), cancellationToken);

            _logger.LogInformation(
                "Account onboarded. AccountId={AccountId} LedgerId={LedgerId}",
                result.AccountId, result.LedgerId);

            return response;
        }
        catch (ConflictException ex)
        {
            _logger.LogWarning("OnboardAccount conflict. Error={Error}", ex.Message);
            return await ProblemAsync(req, ex.Message, HttpStatusCode.Conflict, cancellationToken);
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogWarning("OnboardAccount failed. Error={Error}", ex.Message);
            return await ProblemAsync(req, ex.Message, HttpStatusCode.BadRequest, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "OnboardAccount unexpected error.");
            return await ProblemAsync(req,
                "An unexpected error occurred.", HttpStatusCode.InternalServerError, cancellationToken);
        }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private static async Task<HttpResponseData> ProblemAsync(
        HttpRequestData req,
        string detail,
        HttpStatusCode statusCode,
        CancellationToken cancellationToken)
    {
        var response = req.CreateResponse(statusCode);
        response.Headers.Add("Content-Type", "application/problem+json");
        await response.WriteStringAsync(
            JsonSerializer.Serialize(new OnboardProblemResponse
            {
                Title = statusCode == HttpStatusCode.Conflict
                    ? "Conflict" : statusCode == HttpStatusCode.BadRequest
                    ? "Bad Request" : "Internal Server Error",
                Status = (int)statusCode,
                Detail = detail
            }, _jsonOptions), cancellationToken);
        return response;
    }
}
