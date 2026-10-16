using BottegaAurora.Shop.Catalog;

namespace BottegaAurora.Shop.Checkout;

public sealed record Promo(string Code);

public sealed record CartLine(Product Product, int Quantity)
{
    public decimal Amount => Product.Price * Quantity;
}

public sealed record Cart(IReadOnlyList<CartLine> Lines, Promo? Promo)
{
    public decimal Subtotal => Lines.Sum(l => l.Amount);

    // Human readable summary for the order feed, e.g. "Pandoro x2, Torrone morbido".
    public string Summary =>
        string.Join(", ", Lines.Select(l => l.Quantity > 1 ? $"{l.Product.Name} x{l.Quantity}" : l.Product.Name));
}
