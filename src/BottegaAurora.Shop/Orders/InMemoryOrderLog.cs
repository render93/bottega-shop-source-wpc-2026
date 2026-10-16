namespace BottegaAurora.Shop.Orders;

// Development and tests only: Program refuses to use it outside Development.
public sealed class InMemoryOrderLog(TimeProvider time) : IOrderLog
{
    private readonly List<OrderEntry> _entries = [];
    private readonly Lock _lock = new();

    public Task<long?> RecordCompletedAsync(decimal amount, string items, string? promo) =>
        Task.FromResult<long?>(Add(CheckoutStatus.Completed, amount, items));

    public Task RecordFailedAsync(decimal amount, string items, string? promo)
    {
        Add(CheckoutStatus.Failed, amount, items);
        return Task.CompletedTask;
    }

    public Task<LiveSummary> GetSummaryAsync(DateTimeOffset minuteAgo, DateTimeOffset startOfToday)
    {
        lock (_lock)
        {
            return Task.FromResult(new LiveSummary(
                _entries.Count(e => e.Status == CheckoutStatus.Completed && e.CreatedAt >= minuteAgo),
                _entries.Count(e => e.Status == CheckoutStatus.Failed && e.CreatedAt >= minuteAgo),
                _entries.Where(e => e.Status == CheckoutStatus.Completed && e.CreatedAt >= startOfToday).Sum(e => e.Amount),
                _entries.Where(e => e.Status == CheckoutStatus.Failed && e.CreatedAt >= startOfToday).Sum(e => e.Amount)));
        }
    }

    public Task<IReadOnlyList<OrderEntry>> GetFeedAsync(long? after, int max)
    {
        lock (_lock)
        {
            IEnumerable<OrderEntry> feed = after is null
                ? _entries.TakeLast(max)
                : _entries.Where(e => e.Id > after).Take(max);
            return Task.FromResult<IReadOnlyList<OrderEntry>>(feed.ToList());
        }
    }

    private long Add(string status, decimal amount, string items)
    {
        lock (_lock)
        {
            var entry = new OrderEntry(_entries.Count + 1, time.GetUtcNow(), status, amount, items);
            _entries.Add(entry);
            return entry.Id;
        }
    }
}
