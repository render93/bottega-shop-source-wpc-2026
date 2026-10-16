var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

app.MapGet("/api/version", () => new { version = BottegaAurora.Shop.AppVersion.Current });

app.Run();

public partial class Program;
