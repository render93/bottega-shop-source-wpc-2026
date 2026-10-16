using BottegaAurora.Shop.Checkout;

namespace BottegaAurora.Shop.Tests;

public class PromoCatalogTests
{
    private readonly PromoCatalog _promos = new();

    [Fact]
    public void Resolve_Aurora10_RoundsToCents()
    {
        Assert.Equal(0.95m, _promos.Resolve("AURORA10", 9.50m));
    }

    [Fact]
    public void Resolve_UnknownCode_GivesNoDiscount()
    {
        Assert.Equal(0m, _promos.Resolve("SCONTO50", 100m));
    }
}
