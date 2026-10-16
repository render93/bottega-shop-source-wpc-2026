using System.Net;
using BottegaAurora.Shop.Orders;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;

namespace BottegaAurora.Shop.Tests;

public class UnavailableOrderLogTests : IDisposable
{
    private readonly ShopFactory _factory = new();
    private readonly HttpClient _client;

    public UnavailableOrderLogTests() =>
        _client = _factory.WithWebHostBuilder(b => b.ConfigureTestServices(s => s.AddSingleton<IOrderLog, UnavailableOrderLog>()))
            .CreateClient();

    public void Dispose() => _factory.Dispose();

    private sealed class UnavailableOrderLog : IOrderLog
    {
        public Task<long?> RecordCompletedAsync(decimal amount, string items, string? promo) => Task.FromResult<long?>(null);
        public Task RecordFailedAsync(decimal amount, string items, string? promo) => Task.CompletedTask;
        public Task<LiveSummary> GetSummaryAsync(DateTimeOffset minuteAgo, DateTimeOffset startOfToday) => throw new TimeoutException();
        public Task<IReadOnlyList<OrderEntry>> GetFeedAsync(long? after, int max) => throw new TimeoutException();
    }

    [Theory]
    [InlineData("/api/live")]
    [InlineData("/api/orders/feed")]
    public async Task ReadEndpoints_WhenLogIsUnavailable_Return503(string url)
    {
        var response = await _client.GetAsync(url);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }
}
