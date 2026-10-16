using BottegaAurora.Shop.Orders;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging.Abstractions;

namespace BottegaAurora.Shop.Tests;

// Runs only when SHOP_SQL_TEST_CONNECTION points to a disposable SQL Server database
// (e.g. a local container); otherwise every test is skipped.
public sealed class SqlFactAttribute : FactAttribute
{
    public SqlFactAttribute()
    {
        if (string.IsNullOrEmpty(SqlOrderLogTests.ConnectionString))
        {
            Skip = $"Set {SqlOrderLogTests.ConnectionVariable} to run against SQL Server.";
        }
    }
}

public class SqlOrderLogTests
{
    public const string ConnectionVariable = "SHOP_SQL_TEST_CONNECTION";
    public static string? ConnectionString => Environment.GetEnvironmentVariable(ConnectionVariable);

    private static async Task<SqlOrderLog> FreshLogAsync()
    {
        var migration = await File.ReadAllTextAsync(Path.Combine(RepoRoot(), "db", "migrations", "001_initial.sql"));
        await using var conn = new SqlConnection(ConnectionString);
        await conn.OpenAsync();
        await using (var drop = new SqlCommand("DROP TABLE IF EXISTS dbo.Checkouts;", conn)) await drop.ExecuteNonQueryAsync();
        await using (var create = new SqlCommand(migration, conn)) await create.ExecuteNonQueryAsync();
        return new SqlOrderLog(ConnectionString!, NullLogger<SqlOrderLog>.Instance);
    }

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "BottegaAurora.slnx"))) dir = dir.Parent;
        return dir?.FullName ?? throw new InvalidOperationException("Repository root not found.");
    }

    [SqlFact]
    public async Task RecordAndRead_RoundTrips()
    {
        var log = await FreshLogAsync();

        var id = await log.RecordCompletedAsync(43.20m, "Pandoro x2", null);
        await log.RecordFailedAsync(24.00m, "Pandoro", "AURORA10");

        var now = DateTimeOffset.UtcNow;
        var summary = await log.GetSummaryAsync(now.AddMinutes(-1), BusinessDay.StartOfToday(now));
        Assert.Equal(new LiveSummary(1, 1, 43.20m, 24.00m), summary);

        var feed = await log.GetFeedAsync(after: null, max: 15);
        Assert.Equal([id!.Value, id.Value + 1], feed.Select(e => e.Id));
        Assert.Equal(CheckoutStatus.Failed, feed[1].Status);

        var newer = await log.GetFeedAsync(after: id, max: 50);
        Assert.Equal("Pandoro", Assert.Single(newer).Items);
    }

    [Fact]
    public async Task Record_WhenDatabaseIsUnreachable_ReturnsNullInsteadOfThrowing()
    {
        var log = new SqlOrderLog("Server=127.0.0.1,1;Database=none;User Id=x;Password=y;Connect Timeout=1;Encrypt=false",
            NullLogger<SqlOrderLog>.Instance);

        Assert.Null(await log.RecordCompletedAsync(1m, "Cantucci", null));
    }
}
