namespace BottegaAurora.Shop.Checkout;

public sealed record CheckoutResult(decimal Total, decimal Discount);

public sealed class CheckoutService(PromoCatalog promos)
{
    public CheckoutResult Complete(Cart cart)
    {
        var subtotal = cart.Subtotal;
        var discount = cart.Promo is null ? 0m : promos.Resolve(cart.Promo.Code, subtotal);
        return new CheckoutResult(subtotal - discount, discount);
    }
}
