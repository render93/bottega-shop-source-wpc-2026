using Microsoft.AspNetCore.Mvc.Testing;

namespace BottegaAurora.Shop.Tests;

// WebApplicationFactory runs the app in Development, so it uses InMemoryOrderLog.
public sealed class ShopFactory : WebApplicationFactory<Program>;
