using System.Diagnostics.CodeAnalysis;
using BottegaAurora.Shop.Catalog;

namespace BottegaAurora.Shop.Checkout;

public sealed class CartFactory(ProductCatalog catalog)
{
    public const int MaxQuantity = 10;

    public bool TryCreate(CheckoutRequest request, [NotNullWhen(true)] out Cart? cart, [NotNullWhen(false)] out string? error)
    {
        cart = null;
        if (request.Items is null || request.Items.Count == 0)
        {
            error = "The cart is empty.";
            return false;
        }

        var lines = new List<CartLine>();
        foreach (var item in request.Items)
        {
            if (item?.Sku is null)
            {
                error = "Each item needs a sku.";
                return false;
            }

            var product = catalog.Find(item.Sku);
            if (product is null)
            {
                error = $"Unknown product '{item.Sku}'.";
                return false;
            }
            if (item.Qty is < 1 or > MaxQuantity)
            {
                error = $"Quantity for '{item.Sku}' must be between 1 and {MaxQuantity}.";
                return false;
            }
            lines.Add(new CartLine(product, item.Qty));
        }

        var promo = string.IsNullOrWhiteSpace(request.Promo) ? null : new Promo(request.Promo.Trim());
        cart = new Cart(lines, promo);
        error = null;
        return true;
    }
}
