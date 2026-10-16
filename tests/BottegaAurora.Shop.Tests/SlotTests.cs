using BottegaAurora.Shop.Telemetry;

namespace BottegaAurora.Shop.Tests;

public class SlotTests
{
    [Theory]
    [InlineData("aurora-shop.azurewebsites.net", "production")]
    [InlineData("aurora-shop-staging.azurewebsites.net", "staging")]
    [InlineData("localhost", "local")]
    public void FromHost_DetectsSlot(string host, string expected)
    {
        Assert.Equal(expected, Slot.FromHost(host));
    }
}
