using System.Text.Json;
using Microsoft.Extensions.Logging;
using StackExchange.Redis;

namespace PaymentServices.AccountResolution.Services;

public interface ICacheService
{
    /// <summary>
    /// Gets a cached value by key.
    /// Returns null if not found or Redis is unavailable.
    /// </summary>
    Task<T?> GetAsync<T>(string key, CancellationToken cancellationToken = default)
        where T : class;

    /// <summary>
    /// Sets a value in cache with the given TTL.
    /// Silently swallows errors if Redis is unavailable.
    /// </summary>
    Task SetAsync<T>(string key, T value, TimeSpan ttl, CancellationToken cancellationToken = default)
        where T : class;

    /// <summary>
    /// Removes a cached value by key.
    /// Silently swallows errors if Redis is unavailable.
    /// </summary>
    Task RemoveAsync(string key, CancellationToken cancellationToken = default);
}

/// <summary>
/// No-op cache implementation used when Redis is not configured.
/// Always returns null on get — forces Cosmos fallback.
/// Safe for local development without a Redis instance.
/// </summary>
public sealed class NoOpCacheService : ICacheService
{
    public Task<T?> GetAsync<T>(string key, CancellationToken cancellationToken = default)
        where T : class => Task.FromResult<T?>(null);

    public Task SetAsync<T>(string key, T value, TimeSpan ttl, CancellationToken cancellationToken = default)
        where T : class => Task.CompletedTask;

    public Task RemoveAsync(string key, CancellationToken cancellationToken = default)
        => Task.CompletedTask;
}
/// If Redis is unavailable, all operations succeed silently —
/// the caller falls back to Cosmos without any error propagation.
/// </summary>
public sealed class RedisCacheService : ICacheService
{
    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<RedisCacheService> _logger;

    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public RedisCacheService(
        IConnectionMultiplexer redis,
        ILogger<RedisCacheService> logger)
    {
        _redis = redis;
        _logger = logger;
    }

    public async Task<T?> GetAsync<T>(
        string key,
        CancellationToken cancellationToken = default)
        where T : class
    {
        try
        {
            if (!_redis.IsConnected)
            {
                _logger.LogWarning("Redis unavailable. Cache miss for key={Key}", key);
                return null;
            }

            var db = _redis.GetDatabase();
            var value = await db.StringGetAsync(key);

            if (value.IsNullOrEmpty)
                return null;

            return JsonSerializer.Deserialize<T>(value!, _jsonOptions);
        }
        catch (Exception ex)
        {
            // Silent fallback — Redis failure should never fail a payment
            _logger.LogWarning(ex,
                "Redis GET failed. Falling back to Cosmos. Key={Key}", key);
            return null;
        }
    }

    public async Task SetAsync<T>(
        string key,
        T value,
        TimeSpan ttl,
        CancellationToken cancellationToken = default)
        where T : class
    {
        try
        {
            if (!_redis.IsConnected)
            {
                _logger.LogWarning("Redis unavailable. Skipping cache set for key={Key}", key);
                return;
            }

            var db = _redis.GetDatabase();
            var serialized = JsonSerializer.Serialize(value, _jsonOptions);
            await db.StringSetAsync(key, serialized, ttl);

            _logger.LogDebug("Cache set. Key={Key} TTL={TTL}", key, ttl);
        }
        catch (Exception ex)
        {
            // Silent fallback — cache write failure should never fail a payment
            _logger.LogWarning(ex,
                "Redis SET failed. Key={Key}", key);
        }
    }

    public async Task RemoveAsync(
        string key,
        CancellationToken cancellationToken = default)
    {
        try
        {
            if (!_redis.IsConnected)
                return;

            var db = _redis.GetDatabase();
            await db.KeyDeleteAsync(key);

            _logger.LogDebug("Cache removed. Key={Key}", key);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis DELETE failed. Key={Key}", key);
        }
    }
}
