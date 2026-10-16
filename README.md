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

Every script works on one environment, named by `AURORA_ENV` (1-8 lowercase letters or digits). The environment owns two resource groups: `rg-aurora-prod-<env>` (the shop) and `rg-aurora-agent-<env>` (the SRE Agent). `rg-aurora-ops` (deploy identity and load generator, no cost at rest) is shared by all environments and kept between them. Metrics and alert history are tied to resource IDs, so a new environment name starts with a clean history.

    export AURORA_ENV=dev1
    scripts/deploy-infra.sh                # create or update everything (idempotent)
    scripts/destroy-infra.sh               # dry run: list what would be deleted
    scripts/destroy-infra.sh --yes         # delete the environment's resource groups, keep rg-aurora-ops
    scripts/destroy-infra.sh --yes --all   # delete rg-aurora-ops too

The signed-in user becomes the Microsoft Entra admin of the SQL server; the app's managed identity only reads and writes rows.

## Workflows

- **CI/CD**: tests every pull request and every push that changes `src/` or `tests/`; on `main` it deploys to the staging slot and swaps it into production.
- **Deploy version**: deploys a tag to one slot, without swapping.
- **Promote to production** / **Emergency rollback**: swap staging and production.
- **Preflight**: checks that each slot serves the expected version.

Connect a repository to an environment (after `scripts/deploy-infra.sh`) with `AURORA_ENV=<env> scripts/connect-repo.sh <owner>/<repo>`. It sets the repository variables the workflows read (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `RESOURCE_GROUP`, `WEB_APP`) and gives the deploy identity a federated credential for the repository's `main`, removing those of previously connected repositories.

## Azure SRE Agent

`sre-agent/` holds the agent configuration (subagent, incident response plan, hook, tool permissions, knowledge) with placeholders for resource IDs. Create the agent after the infrastructure:

    AURORA_ENV=<env> TEAMS_GROUP_ID=<team id> TEAMS_CHANNEL_ID=<channel id> AGENT_GITHUB_PAT=<token> \
      scripts/deploy-agent.sh <owner>/<repo>

The agent is created in `rg-aurora-agent-<env>` and watches `rg-aurora-prod-<env>`.

`AGENT_GITHUB_PAT` is a fine-grained token limited to that repository (Contents, Pull requests, Issues: read and write). The script prints the remaining manual steps (onboarding and the Teams connector need an interactive sign-in).

## Preparing a complete environment

    AURORA_ENV=<old env> scripts/destroy-infra.sh --yes   # remove the previous environment
    scripts/prepare-stage.sh <env> <owner>/<copy>         # copy the repository, deploy everything (TEAMS_*, AGENT_GITHUB_PAT)
    AURORA_ENV=<env> scripts/preflight.sh <owner>/<copy>  # read-only check, one line per item (needs AGENT_GITHUB_PAT)
    AURORA_ENV=<env> scripts/start-traffic.sh             # about 12 checkouts per minute
    scripts/stop-traffic.sh

Each environment name is single-use. `prepare-stage.sh` refuses a name that was already used (its subscription deployment `bottega-aurora-infra-<env>` exists, or its workload group appears in the alert history of the last 30 days): metrics and alert history of its resources would be visible to the agent. A failed preparation burns the name too: destroy it and use a new one. The Web App and the other resources keep the same names in every environment, so only one environment can exist at a time: `prepare-stage.sh` also refuses while any `rg-aurora-prod-*` or `rg-aurora-agent-*` group exists, or while a group is being deleted.

`copy-repo.sh` deletes and recreates the copy: it needs the `delete_repo` scope (`gh auth refresh -h github.com -s delete_repo`).
