using BottegaAurora.Shop.Catalog;
using BottegaAurora.Shop.Checkout;

namespace BottegaAurora.Shop.Tests;

public class CartFactoryTests
{
    private readonly CartFactory _carts = new(new ProductCatalog());

    [Fact]
    public void TryCreate_PricesLinesFromCatalog()
    {
        var ok = _carts.TryCreate(new CheckoutRequest([new("pandoro", 2), new("torrone", 1)], "AURORA10"), out var cart, out _);

        Assert.True(ok);
        Assert.Equal(62.50m, cart!.Subtotal);
        Assert.Equal("Pandoro x2, Torrone morbido", cart.Summary);
        Assert.Equal("AURORA10", cart.Promo!.Code);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void TryCreate_BlankPromo_IsIgnored(string? promo)
    {
        _carts.TryCreate(new CheckoutRequest([new("cantucci", 1)], promo), out var cart, out _);

        Assert.Null(cart!.Promo);
    }

    [Fact]
    public void TryCreate_EmptyCart_Fails()
    {
        Assert.False(_carts.TryCreate(new CheckoutRequest([], null), out _, out var error));
        Assert.Equal("The cart is empty.", error);
    }

    [Fact]
    public void TryCreate_UnknownSku_Fails()
    {
        Assert.False(_carts.TryCreate(new CheckoutRequest([new("colomba", 1)], null), out _, out var error));
        Assert.Contains("colomba", error);
    }

    [Fact]
    public void TryCreate_ItemWithoutSku_Fails()
    {
        Assert.False(_carts.TryCreate(new CheckoutRequest([new(null!, 1)], null), out _, out var error));
        Assert.Equal("Each item needs a sku.", error);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(11)]
    public void TryCreate_QuantityOutOfRange_Fails(int qty)
    {
        Assert.False(_carts.TryCreate(new CheckoutRequest([new("pandoro", qty)], null), out _, out _));
    }
}
