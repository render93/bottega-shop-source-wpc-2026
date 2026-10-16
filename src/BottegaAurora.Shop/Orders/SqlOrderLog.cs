using System.Data;
using Microsoft.Data.SqlClient;

namespace BottegaAurora.Shop.Orders;

// Orders live in Azure SQL: the live counter reads the shop's own data, not Application
// Insights (ingestion delay). Schema: db/migrations, applied outside the app.
public sealed class SqlOrderLog(string connectionString, ILogger<SqlOrderLog> log) : IOrderLog
{
    private const string InsertSql = """
        INSERT INTO dbo.Checkouts (Status, Amount, Items, Promo)
        OUTPUT INSERTED.Id
        VALUES (@status, @amount, @items, @promo);
        """;

    public async Task<long?> RecordCompletedAsync(decimal amount, string items, string? promo) =>
        await InsertAsync(CheckoutStatus.Completed, amount, items, promo);

    public async Task RecordFailedAsync(decimal amount, string items, string? promo) =>
        await InsertAsync(CheckoutStatus.Failed, amount, items, promo);

    public async Task<LiveSummary> GetSummaryAsync(DateTimeOffset minuteAgo, DateTimeOffset startOfToday)
    {
        await using var conn = new SqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new SqlCommand("""
            SELECT
                (SELECT COUNT(*) FROM dbo.Checkouts WHERE Status = 'Completed' AND CreatedAt >= @minuteAgo),
                (SELECT COUNT(*) FROM dbo.Checkouts WHERE Status = 'Failed' AND CreatedAt >= @minuteAgo),
                (SELECT ISNULL(SUM(Amount), 0) FROM dbo.Checkouts WHERE Status = 'Completed' AND CreatedAt >= @startOfToday),
                (SELECT ISNULL(SUM(Amount), 0) FROM dbo.Checkouts WHERE Status = 'Failed' AND CreatedAt >= @startOfToday);
            """, conn);
        cmd.Parameters.Add("@minuteAgo", SqlDbType.DateTime2).Value = minuteAgo.UtcDateTime;
        cmd.Parameters.Add("@startOfToday", SqlDbType.DateTime2).Value = startOfToday.UtcDateTime;
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        return new LiveSummary(reader.GetInt32(0), reader.GetInt32(1), reader.GetDecimal(2), reader.GetDecimal(3));
    }

    public async Task<IReadOnlyList<OrderEntry>> GetFeedAsync(long? after, int max)
    {
        await using var conn = new SqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(after is null
            ? "SELECT TOP (@max) Id, CreatedAt, Status, Amount, Items FROM dbo.Checkouts ORDER BY Id DESC"
            : "SELECT TOP (@max) Id, CreatedAt, Status, Amount, Items FROM dbo.Checkouts WHERE Id > @after ORDER BY Id", conn);
        cmd.Parameters.Add("@max", SqlDbType.Int).Value = max;
        cmd.Parameters.Add("@after", SqlDbType.BigInt).Value = after ?? 0;
        var entries = new List<OrderEntry>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var createdAt = DateTime.SpecifyKind(reader.GetDateTime(1), DateTimeKind.Utc);
            entries.Add(new OrderEntry(reader.GetInt64(0), createdAt, reader.GetString(2), reader.GetDecimal(3), reader.GetString(4)));
        }
        if (after is null) entries.Reverse();
        return entries;
    }

    private async Task<long?> InsertAsync(string status, decimal amount, string items, string? promo)
    {
        try
        {
            await using var conn = new SqlConnection(connectionString);
            await conn.OpenAsync();
            await using var cmd = new SqlCommand(InsertSql, conn);
            cmd.Parameters.Add("@status", SqlDbType.VarChar, 16).Value = status;
            cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = amount;
            cmd.Parameters["@amount"].Precision = 10;
            cmd.Parameters["@amount"].Scale = 2;
            cmd.Parameters.Add("@items", SqlDbType.NVarChar, 200).Value = Truncate(items, 200);
            cmd.Parameters.Add("@promo", SqlDbType.NVarChar, 32).Value = (object?)promo ?? DBNull.Value;
            return (long)(await cmd.ExecuteScalarAsync())!;
        }
        catch (Exception ex)
        {
            log.LogWarning(ex, "Could not record {Status} checkout", status);
            return null;
        }
    }

    private static string Truncate(string value, int length) => value.Length <= length ? value : value[..length];
}
