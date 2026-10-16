namespace BottegaAurora.Shop.Checkout;

public sealed class PromoCatalog
{
    private static readonly Dictionary<string, decimal> PercentOff = new()
    {
        ["AURORA10"] = 10m,
    };

    // Discount in euros for the given code; unknown codes give no discount.
    public decimal Resolve(string code, decimal subtotal) =>
        PercentOff.TryGetValue(code, out var percent)
            ? Math.Round(subtotal * percent / 100m, 2, MidpointRounding.AwayFromZero)
            : 0m;
}
