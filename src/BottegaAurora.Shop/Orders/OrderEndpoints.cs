namespace BottegaAurora.Shop.Orders;

public static class OrderEndpoints
{
    public const int LatestCount = 15;
    public const int MaxPage = 50;

    public static void MapOrders(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/live", async (IOrderLog orders, TimeProvider time, ILogger<IOrderLog> log) =>
        {
            var now = time.GetUtcNow();
            try
            {
                var s = await orders.GetSummaryAsync(now.AddMinutes(-1), BusinessDay.StartOfToday(now));
                return Results.Ok(new
                {
                    version = AppVersion.Current,
                    ordersLastMinute = s.OrdersLastMinute,
                    failedLastMinute = s.FailedLastMinute,
                    revenueToday = s.RevenueToday,
                    lostToday = s.LostToday,
                });
            }
            catch (Exception ex)
            {
                log.LogWarning(ex, "Live summary unavailable");
                return Results.StatusCode(StatusCodes.Status503ServiceUnavailable);
            }
        });

        app.MapGet("/api/orders/feed", async (long? after, IOrderLog orders, ILogger<IOrderLog> log) =>
        {
            try
            {
                return Results.Ok(await orders.GetFeedAsync(after, after is null ? LatestCount : MaxPage));
            }
            catch (Exception ex)
            {
                log.LogWarning(ex, "Order feed unavailable");
                return Results.StatusCode(StatusCodes.Status503ServiceUnavailable);
            }
        });
    }
}
