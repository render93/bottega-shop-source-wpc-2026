using System.Net;
using System.Net.Http.Json;
using BottegaAurora.Shop.Orders;

namespace BottegaAurora.Shop.Tests;

// One factory per test: each test gets its own InMemoryOrderLog.
public class ShopApiTests : IDisposable
{
    private readonly ShopFactory _factory = new();
    private readonly HttpClient _client;

    public ShopApiTests() => _client = _factory.CreateClient();

    public void Dispose() => _factory.Dispose();

    private sealed record CheckoutResponse(long? OrderId, decimal Total, decimal Discount);
    private sealed record LiveResponse(string Version, int OrdersLastMinute, int FailedLastMinute, decimal RevenueToday, decimal LostToday);

    private Task<HttpResponseMessage> CheckoutAsync(object body) => _client.PostAsJsonAsync("/api/checkout", body);

    [Fact]
    public async Task Checkout_WithPromo_ReturnsOrder()
    {
        var response = await CheckoutAsync(new { items = new[] { new { sku = "panettone-classico", qty = 1 } }, promo = "AURORA10" });

        response.EnsureSuccessStatusCode();
        var order = await response.Content.ReadFromJsonAsync<CheckoutResponse>();
        Assert.Equal(1, order!.OrderId);
        Assert.Equal(28.80m, order.Total);
        Assert.Equal(3.20m, order.Discount);
    }

    [Fact]
    public async Task Checkout_UnknownSku_Returns400AndRecordsNothing()
    {
        var response = await CheckoutAsync(new { items = new[] { new { sku = "colomba", qty = 1 } }, promo = "AURORA10" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Empty((await _client.GetFromJsonAsync<List<OrderEntry>>("/api/orders/feed"))!);
    }

    [Fact]
    public async Task Live_AfterCheckout_CountsOrderAndRevenue()
    {
        await CheckoutAsync(new { items = new[] { new { sku = "pandoro", qty = 2 } }, promo = "AURORA10" });

        var live = await _client.GetFromJsonAsync<LiveResponse>("/api/live");

        Assert.Equal(AppVersion.Current, live!.Version);
        Assert.Equal(1, live.OrdersLastMinute);
        Assert.Equal(0, live.FailedLastMinute);
        Assert.Equal(43.20m, live.RevenueToday);
        Assert.Equal(0m, live.LostToday);
    }

    [Fact]
    public async Task Feed_WithCursor_ReturnsOnlyNewOrders()
    {
        for (var i = 0; i < 3; i++)
            await CheckoutAsync(new { items = new[] { new { sku = "cantucci", qty = 1 } }, promo = "AURORA10" });

        var feed = (await _client.GetFromJsonAsync<List<OrderEntry>>("/api/orders/feed?after=1"))!;

        Assert.Equal([2L, 3L], feed.Select(e => e.Id));
        Assert.All(feed, e => Assert.Equal("Cantucci", e.Items));
    }

    [Fact]
    public async Task Home_ServesStorefront()
    {
        var html = await _client.GetStringAsync("/");

        Assert.Contains("Bottega Aurora", html);
    }
}
