namespace BottegaAurora.Shop.Orders;

// The shop's day starts at midnight in Italy, not UTC.
public static class BusinessDay
{
    private static readonly TimeZoneInfo Italy = TimeZoneInfo.FindSystemTimeZoneById("Europe/Rome");

    public static DateTimeOffset StartOfToday(DateTimeOffset now)
    {
        var local = TimeZoneInfo.ConvertTime(now, Italy);
        var midnight = new DateTime(local.Year, local.Month, local.Day, 0, 0, 0, DateTimeKind.Unspecified);
        return new DateTimeOffset(midnight, Italy.GetUtcOffset(midnight)).ToUniversalTime();
    }
}
