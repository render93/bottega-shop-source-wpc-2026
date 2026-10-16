namespace BottegaAurora.Shop.Checkout;

public sealed record CheckoutItem(string Sku, int Qty);

public sealed record CheckoutRequest(IReadOnlyList<CheckoutItem>? Items, string? Promo);
