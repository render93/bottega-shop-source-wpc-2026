using BottegaAurora.Shop.Telemetry;

namespace BottegaAurora.Shop.Tests;

public class SlotTests
{
    [Theory]
    [InlineData("aurora-shop.azurewebsites.net", "production")]
    [InlineData("aurora-shop-staging.azurewebsites.net", "staging")]
    [InlineData("localhost", "local")]
    [InlineData("aurora-shop-staging-a1b2c3d4e5f6g7h8.italynorth-01.azurewebsites.net", "staging")]
    [InlineData("aurora-shop-a1b2c3d4e5f6g7h8.italynorth-01.azurewebsites.net", "production")]
    [InlineData("Aurora-Shop-Staging.azurewebsites.net", "staging")]
    [InlineData("127.0.0.1", "local")]
    public void FromHost_DetectsSlot(string host, string expected)
    {
        Assert.Equal(expected, Slot.FromHost(host));
    }
}
