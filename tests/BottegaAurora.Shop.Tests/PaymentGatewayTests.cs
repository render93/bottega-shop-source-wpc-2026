using BottegaAurora.Shop.Payments;
using Microsoft.Extensions.Configuration;

namespace BottegaAurora.Shop.Tests;

public class PaymentGatewayTests
{
    private static PaymentGateway GatewayWith(Dictionary<string, string?> settings) =>
        new(new ConfigurationBuilder().AddInMemoryCollection(settings).Build());

    [Fact]
    public void Timeout_WhenNotConfigured_Is3000Ms()
    {
        var gateway = GatewayWith([]);

        Assert.Equal(TimeSpan.FromMilliseconds(3000), gateway.Timeout);
    }

    [Fact]
    public void Timeout_ReadsPaymentTimeoutMs()
    {
        var gateway = GatewayWith(new() { ["PAYMENT_TIMEOUT_MS"] = "8000" });

        Assert.Equal(TimeSpan.FromMilliseconds(8000), gateway.Timeout);
    }

    [Fact]
    public async Task AuthorizeAsync_WithinTimeout_ReturnsReference()
    {
        var gateway = GatewayWith([]);

        var reference = await gateway.AuthorizeAsync(28.80m, CancellationToken.None);

        Assert.False(string.IsNullOrWhiteSpace(reference));
    }

    [Fact]
    public async Task AuthorizeAsync_WhenTimeoutElapses_ThrowsTimeoutException()
    {
        var gateway = GatewayWith(new() { ["PAYMENT_TIMEOUT_MS"] = "1" });

        var error = await Assert.ThrowsAsync<TimeoutException>(() => gateway.AuthorizeAsync(28.80m, CancellationToken.None));
        Assert.Equal("Payment authorization timed out after 1 ms", error.Message);
    }
}
