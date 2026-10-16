using BottegaAurora.Shop;
using BottegaAurora.Shop.Catalog;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<ProductCatalog>();

var app = builder.Build();

app.MapGet("/api/version", () => new { version = AppVersion.Current });
app.MapCatalog();

app.Run();

public partial class Program;
