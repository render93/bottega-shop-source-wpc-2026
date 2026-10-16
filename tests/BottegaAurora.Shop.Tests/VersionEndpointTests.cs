using System.Net.Http.Json;

namespace BottegaAurora.Shop.Tests;

public class VersionEndpointTests(ShopFactory factory) : IClassFixture<ShopFactory>
{
    private sealed record VersionResponse(string Version);

    [Fact]
    public async Task GetVersion_ReturnsAssemblyVersion()
    {
        var response = await factory.CreateClient().GetFromJsonAsync<VersionResponse>("/api/version");

        Assert.Equal(AppVersion.Current, response!.Version);
        Assert.Matches(@"^\d+\.\d+\.\d+$", response.Version);
    }
}
