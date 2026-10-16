# Bottega Aurora

Online shop of Bottega Aurora, artisan bakery: panettoni and holiday sweets.

- Storefront and control room: `/` and `/#sala`
- API: `GET /api/products`, `POST /api/checkout`, `GET /api/live`, `GET /api/orders/feed`, `GET /api/version`
- Orders are stored in Azure SQL (`db/migrations`); `ConnectionStrings:Shop` is required outside Development
- Synthetic traffic: `loadgen/checkout.js` (k6)

## Run locally

    ASPNETCORE_ENVIRONMENT=Development dotnet run --project src/BottegaAurora.Shop

Development uses an in-memory order log. Tests: `dotnet test`.

## Azure infrastructure

Prerequisites: Azure CLI logged in to the target subscription, `sqlcmd` (go-sqlcmd), `jq`.

    scripts/deploy-infra.sh          # create or update everything (idempotent)
    scripts/destroy-infra.sh         # dry run: list what would be deleted
    scripts/destroy-infra.sh --yes   # delete the resource groups

The signed-in user becomes the Microsoft Entra admin of the SQL server; the app's managed identity only reads and writes rows.
