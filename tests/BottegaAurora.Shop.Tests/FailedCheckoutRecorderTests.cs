using BottegaAurora.Shop.Catalog;
using BottegaAurora.Shop.Checkout;
using BottegaAurora.Shop.Orders;
using Microsoft.AspNetCore.Http;

namespace BottegaAurora.Shop.Tests;

public class FailedCheckoutRecorderTests
{
    private readonly InMemoryOrderLog _log = new(TimeProvider.System);
    private readonly Cart _cart = new([new CartLine(new ProductCatalog().Find("pandoro")!, 2)], new Promo("AURORA10"));

    private DefaultHttpContext CheckoutContext()
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Post;
        context.Request.Path = CheckoutEndpoints.Route;
        context.Items[CheckoutEndpoints.PricedCartKey] = _cart;
        return context;
    }

    [Fact]
    public async Task WhenCheckoutThrows_RecordsFailedCartAndRethrows()
    {
        var recorder = new FailedCheckoutRecorder(_ => throw new InvalidOperationException("boom"));

        await Assert.ThrowsAsync<InvalidOperationException>(() => recorder.InvokeAsync(CheckoutContext(), _log));

        var entry = Assert.Single(await _log.GetFeedAsync(null, 50));
        Assert.Equal(CheckoutStatus.Failed, entry.Status);
        Assert.Equal(48.00m, entry.Amount);
        Assert.Equal("Pandoro x2", entry.Items);
    }

    [Fact]
    public async Task WhenCheckoutReturns503_RecordsFailedCart()
    {
        var recorder = new FailedCheckoutRecorder(ctx =>
        {
            ctx.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            return Task.CompletedTask;
        });

        await recorder.InvokeAsync(CheckoutContext(), _log);

        Assert.Single(await _log.GetFeedAsync(null, 50));
    }

    [Fact]
    public async Task WhenCheckoutSucceeds_RecordsNothing()
    {
        var recorder = new FailedCheckoutRecorder(_ => Task.CompletedTask);

        await recorder.InvokeAsync(CheckoutContext(), _log);

        Assert.Empty(await _log.GetFeedAsync(null, 50));
    }

    [Fact]
    public async Task OtherRoutes_AreNotRecorded()
    {
        var recorder = new FailedCheckoutRecorder(_ => throw new InvalidOperationException("boom"));
        var context = CheckoutContext();
        context.Request.Path = "/api/products";

        await Assert.ThrowsAsync<InvalidOperationException>(() => recorder.InvokeAsync(context, _log));

        Assert.Empty(await _log.GetFeedAsync(null, 50));
    }
}
