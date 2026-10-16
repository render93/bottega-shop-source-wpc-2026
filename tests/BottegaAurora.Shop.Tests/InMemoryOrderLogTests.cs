using BottegaAurora.Shop.Orders;
using Microsoft.Extensions.Time.Testing;

namespace BottegaAurora.Shop.Tests;

public class InMemoryOrderLogTests
{
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 26, 14, 0, 0, TimeSpan.Zero));
    private readonly InMemoryOrderLog _log;

    public InMemoryOrderLogTests() => _log = new InMemoryOrderLog(_time);

    [Fact]
    public async Task Summary_CountsLastMinuteAndSumsToday()
    {
        await _log.RecordCompletedAsync(10m, "Cantucci", null);
        _time.Advance(TimeSpan.FromMinutes(2));
        await _log.RecordCompletedAsync(20m, "Pandoro", null);
        await _log.RecordFailedAsync(35m, "Panforte", null);

        var now = _time.GetUtcNow();
        var s = await _log.GetSummaryAsync(now.AddMinutes(-1), BusinessDay.StartOfToday(now));

        Assert.Equal(new LiveSummary(1, 1, 30m, 35m), s);
    }

    [Fact]
    public async Task Feed_WithoutCursor_ReturnsLatestInAscendingOrder()
    {
        for (var i = 1; i <= 5; i++) await _log.RecordCompletedAsync(i, $"Item {i}", null);

        var feed = await _log.GetFeedAsync(after: null, max: 3);

        Assert.Equal([3L, 4L, 5L], feed.Select(e => e.Id));
    }

    [Fact]
    public async Task Feed_WithCursor_ReturnsOnlyNewerEntries()
    {
        await _log.RecordCompletedAsync(1m, "A", null);
        await _log.RecordFailedAsync(2m, "B", null);
        await _log.RecordCompletedAsync(3m, "C", null);

        var feed = await _log.GetFeedAsync(after: 1, max: 50);

        Assert.Equal([2L, 3L], feed.Select(e => e.Id));
        Assert.Equal(CheckoutStatus.Failed, feed[0].Status);
    }
}
