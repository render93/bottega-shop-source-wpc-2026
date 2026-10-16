using BottegaAurora.Shop.Orders;

namespace BottegaAurora.Shop.Checkout;

// Lost euros = carts that failed to pay. The failure is recorded and rethrown, never
// swallowed: the client still gets a real 500 and telemetry gets the real exception.
public sealed class FailedCheckoutRecorder(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, IOrderLog orders)
    {
        if (!IsCheckout(context.Request))
        {
            await next(context);
            return;
        }

        try
        {
            await next(context);
        }
        catch
        {
            await RecordAsync(context, orders);
            throw;
        }

        if (context.Response.StatusCode >= StatusCodes.Status500InternalServerError)
        {
            await RecordAsync(context, orders);
        }
    }

    private static bool IsCheckout(HttpRequest request) =>
        HttpMethods.IsPost(request.Method) &&
        request.Path.Equals(CheckoutEndpoints.Route, StringComparison.OrdinalIgnoreCase);

    private static Task RecordAsync(HttpContext context, IOrderLog orders) =>
        context.Items[CheckoutEndpoints.PricedCartKey] is Cart cart
            ? orders.RecordFailedAsync(cart.Subtotal, cart.Summary, cart.Promo?.Code)
            : Task.CompletedTask;
}
