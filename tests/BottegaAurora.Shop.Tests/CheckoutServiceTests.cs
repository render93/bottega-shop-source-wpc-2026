using BottegaAurora.Shop.Catalog;
using BottegaAurora.Shop.Checkout;

namespace BottegaAurora.Shop.Tests;

public class CheckoutServiceTests
{
    private readonly ProductCatalog _catalog = new();
    private readonly CheckoutService _checkout = new(new PromoCatalog());

    private Cart CartOf(string sku, int qty, string promo) =>
        new([new CartLine(_catalog.Find(sku)!, qty)], new Promo(promo));

    [Fact]
    public void Complete_WithAurora10_TakesTenPercentOff()
    {
        var result = _checkout.Complete(CartOf("panettone-classico", 2, "AURORA10"));

        Assert.Equal(6.40m, result.Discount);
        Assert.Equal(57.60m, result.Total);
    }

    [Fact]
    public void Complete_WithUnknownCode_ChargesFullPrice()
    {
        var result = _checkout.Complete(CartOf("torrone", 1, "SCONTO50"));

        Assert.Equal(0m, result.Discount);
        Assert.Equal(14.50m, result.Total);
    }
}
