namespace BottegaAurora.Shop.Catalog;

public sealed class ProductCatalog
{
    private static readonly Product[] Products =
    [
        new("panettone-classico", "Panettone classico", "Lievitato 36 ore, uvetta e canditi d'arancia", 32.00m),
        new("panettone-cioccolato", "Panettone al cioccolato", "Gocce di cioccolato fondente al 70%", 36.00m),
        new("pandoro", "Pandoro", "Burro di montagna e vaniglia Bourbon", 24.00m),
        new("pandoro-farcito", "Pandoro farcito", "Crema al mascarpone in vasetto", 29.50m),
        new("torrone", "Torrone morbido", "Mandorle di Avola e miele millefiori", 14.50m),
        new("panforte", "Panforte", "Ricetta senese con spezie e frutta candita", 18.00m),
        new("ricciarelli", "Ricciarelli", "Scatola da 12, pasta di mandorle", 16.00m),
        new("cantucci", "Cantucci", "Sacchetto da 500 g con mandorle intere", 9.50m),
    ];

    private static readonly Dictionary<string, Product> BySku = Products.ToDictionary(p => p.Sku);

    public IReadOnlyList<Product> All => Products;

    public Product? Find(string sku) => BySku.GetValueOrDefault(sku);
}
