namespace BottegaAurora.Shop.Checkout;

public sealed record PromoRule(string Code, decimal PercentOff)
{
    public decimal Apply(decimal subtotal) =>
        Math.Round(subtotal * PercentOff / 100m, 2, MidpointRounding.AwayFromZero);
}

public sealed class PromoCatalog
{
    // Codes are matched case-insensitively: customers type "blackfriday" as often as "BLACKFRIDAY".
    private static readonly Dictionary<string, PromoRule> Rules = new(StringComparer.OrdinalIgnoreCase)
    {
        ["AURORA10"] = new("AURORA10", 10m),
        ["BLACKFRIDAY"] = new("BLACKFRIDAY", 20m),
    };

    public PromoRule? Find(string code) => Rules.GetValueOrDefault(code);
}
