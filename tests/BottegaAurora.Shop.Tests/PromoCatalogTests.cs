using BottegaAurora.Shop.Checkout;

namespace BottegaAurora.Shop.Tests;

public class PromoCatalogTests
{
    private readonly PromoCatalog _promos = new();

    [Fact]
    public void Find_Aurora10_RoundsToCents()
    {
        Assert.Equal(0.95m, _promos.Find("AURORA10")!.Apply(9.50m));
    }

    [Fact]
    public void Find_BlackFriday_TakesTwentyPercentOff()
    {
        Assert.Equal(20m, _promos.Find("BLACKFRIDAY")!.PercentOff);
    }

    [Theory]
    [InlineData("blackfriday")]
    [InlineData("BlackFriday")]
    public void Find_IgnoresCase(string code)
    {
        Assert.Equal("BLACKFRIDAY", _promos.Find(code)!.Code);
    }

    [Fact]
    public void Find_UnknownCode_ReturnsNull()
    {
        Assert.Null(_promos.Find("SCONTO50"));
    }
}
