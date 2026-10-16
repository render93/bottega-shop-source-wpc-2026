using BottegaAurora.Shop.Orders;
using BottegaAurora.Shop.Payments;

namespace BottegaAurora.Shop.Checkout;

public static class CheckoutEndpoints
{
    public const string Route = "/api/checkout";

    // The priced cart is stored here before checkout runs, so FailedCheckoutRecorder
    // can record its value if checkout fails.
    public const string PricedCartKey = "BottegaAurora.PricedCart";

    public static void MapCheckout(this IEndpointRouteBuilder app) =>
        app.MapPost(Route, async (CheckoutRequest request, HttpContext http, CartFactory carts, CheckoutService checkout, PaymentGateway gateway, IOrderLog orders) =>
        {
            if (!carts.TryCreate(request, out var cart, out var error))
            {
                return Results.BadRequest(new { error });
            }

            http.Items[PricedCartKey] = cart;
            var result = checkout.Complete(cart);
            await gateway.AuthorizeAsync(result.Total, http.RequestAborted);
            var orderId = await orders.RecordCompletedAsync(result.Total, cart.Summary, cart.Promo?.Code);
            return Results.Ok(new { orderId, total = result.Total, discount = result.Discount });
        });
}
