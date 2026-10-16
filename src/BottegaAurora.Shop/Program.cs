using BottegaAurora.Shop;
using BottegaAurora.Shop.Catalog;
using BottegaAurora.Shop.Checkout;
using BottegaAurora.Shop.Orders;
using BottegaAurora.Shop.Telemetry;

var builder = WebApplication.CreateBuilder(args);

builder.AddShopTelemetry();
builder.Services.AddProblemDetails();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<ProductCatalog>();
builder.Services.AddSingleton<CartFactory>();
builder.Services.AddSingleton<PromoCatalog>();
builder.Services.AddSingleton<CheckoutService>();

var connectionString = builder.Configuration.GetConnectionString("Shop");
if (!string.IsNullOrEmpty(connectionString))
{
    builder.Services.AddSingleton<IOrderLog>(sp =>
        new SqlOrderLog(connectionString, sp.GetRequiredService<ILogger<SqlOrderLog>>()));
}
else if (builder.Environment.IsDevelopment())
{
    builder.Services.AddSingleton<IOrderLog, InMemoryOrderLog>();
}
else
{
    // Fail fast: an in-memory log would give each instance a different counter.
    throw new InvalidOperationException("ConnectionStrings:Shop is required outside Development.");
}

var app = builder.Build();

app.UseExceptionHandler();
app.UseMiddleware<FailedCheckoutRecorder>();

app.MapGet("/api/version", () => new { version = AppVersion.Current });
app.MapCatalog();
app.MapCheckout();
app.MapOrders();

app.Run();

public partial class Program;
