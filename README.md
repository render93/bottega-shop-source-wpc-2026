# Bottega Aurora

Online shop of Bottega Aurora, artisan bakery: panettoni and holiday sweets.

- Storefront and control room: `/` and `/#sala`
- API: `GET /api/products`, `POST /api/checkout`, `GET /api/live`, `GET /api/orders/feed`, `GET /api/version`
- Orders are stored in Azure SQL (`db/migrations`); `ConnectionStrings:Shop` is required outside Development
- Synthetic traffic: `loadgen/checkout.js` (k6)

## Run locally

    ASPNETCORE_ENVIRONMENT=Development dotnet run --project src/BottegaAurora.Shop

Development uses an in-memory order log. Tests: `dotnet test`.
