namespace BottegaAurora.Shop.Catalog;

public static class CatalogEndpoints
{
    public static void MapCatalog(this IEndpointRouteBuilder app) =>
        app.MapGet("/api/products", (ProductCatalog catalog) => catalog.All);
}
