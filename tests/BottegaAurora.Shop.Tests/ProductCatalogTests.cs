using System.Net.Http.Json;
using BottegaAurora.Shop.Catalog;

namespace BottegaAurora.Shop.Tests;

public class ProductCatalogTests(ShopFactory factory) : IClassFixture<ShopFactory>
{
    private readonly ProductCatalog _catalog = new();

    [Fact]
    public void All_HasEightProductsWithUniqueSkus()
    {
        Assert.Equal(8, _catalog.All.Count);
        Assert.Equal(8, _catalog.All.Select(p => p.Sku).Distinct().Count());
    }

    [Fact]
    public void Find_KnownSku_ReturnsProduct()
    {
        Assert.Equal(24.00m, _catalog.Find("pandoro")!.Price);
    }

    [Fact]
    public void Find_UnknownSku_ReturnsNull()
    {
        Assert.Null(_catalog.Find("colomba"));
    }

    [Fact]
    public async Task GetProducts_ReturnsCatalog()
    {
        var products = await factory.CreateClient().GetFromJsonAsync<List<Product>>("/api/products");

        Assert.Equal(_catalog.All.Select(p => p.Sku), products!.Select(p => p.Sku));
    }
}
