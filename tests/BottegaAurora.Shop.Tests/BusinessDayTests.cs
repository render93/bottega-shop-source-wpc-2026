using BottegaAurora.Shop.Orders;

namespace BottegaAurora.Shop.Tests;

public class BusinessDayTests
{
    [Fact]
    public void StartOfToday_UsesItalianMidnight()
    {
        // 23:30 UTC on 26 Nov is 00:30 on 27 Nov in Italy (UTC+1): the day started at 23:00 UTC.
        var start = BusinessDay.StartOfToday(new DateTimeOffset(2026, 11, 26, 23, 30, 0, TimeSpan.Zero));

        Assert.Equal(new DateTimeOffset(2026, 11, 26, 23, 0, 0, TimeSpan.Zero), start);
    }

    [Fact]
    public void StartOfToday_InSummerTime_IsTwoHoursBeforeUtcMidnight()
    {
        var start = BusinessDay.StartOfToday(new DateTimeOffset(2026, 7, 1, 12, 0, 0, TimeSpan.Zero));

        Assert.Equal(new DateTimeOffset(2026, 6, 30, 22, 0, 0, TimeSpan.Zero), start);
    }
}
