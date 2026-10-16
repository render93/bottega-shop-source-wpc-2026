using BottegaAurora.Shop;
using BottegaAurora.Shop.Catalog;
using BottegaAurora.Shop.Checkout;
using BottegaAurora.Shop.Orders;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<ProductCatalog>();
builder.Services.AddSingleton<CartFactory>();
builder.Services.AddSingleton<PromoCatalog>();
builder.Services.AddSingleton<CheckoutService>();
builder.Services.AddSingleton<IOrderLog, InMemoryOrderLog>();

var app = builder.Build();

app.UseMiddleware<FailedCheckoutRecorder>();

app.MapGet("/api/version", () => new { version = AppVersion.Current });
app.MapCatalog();
app.MapCheckout();
app.MapOrders();

app.Run();

public partial class Program;
