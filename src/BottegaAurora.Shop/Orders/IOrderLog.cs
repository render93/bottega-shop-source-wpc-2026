namespace BottegaAurora.Shop.Orders;

public static class CheckoutStatus
{
    public const string Completed = "Completed";
    public const string Failed = "Failed";
}

public sealed record OrderEntry(long Id, DateTimeOffset CreatedAt, string Status, decimal Amount, string Items);

public sealed record LiveSummary(int OrdersLastMinute, int FailedLastMinute, decimal RevenueToday, decimal LostToday);

// Completed and failed checkouts, read back by the live counter and the order feed.
// Writes must never change the checkout outcome: implementations log failures instead of throwing.
public interface IOrderLog
{
    /// <returns>The order id, or null when the order could not be recorded.</returns>
    Task<long?> RecordCompletedAsync(decimal amount, string items, string? promo);

    Task RecordFailedAsync(decimal amount, string items, string? promo);

    Task<LiveSummary> GetSummaryAsync(DateTimeOffset minuteAgo, DateTimeOffset startOfToday);

    /// <summary>Orders with Id greater than <paramref name="after"/>, or the latest ones when null; always in ascending Id order.</summary>
    Task<IReadOnlyList<OrderEntry>> GetFeedAsync(long? after, int max);
}
