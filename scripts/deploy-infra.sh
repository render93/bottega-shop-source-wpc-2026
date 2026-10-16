#!/usr/bin/env bash
# Deploys (or updates) the Bottega Aurora infrastructure and prepares the database.
# Idempotent: safe to run again. Requires az (logged in to the target subscription), sqlcmd
# (go-sqlcmd: `brew install sqlcmd`), jq and curl.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCATION="${LOCATION:-italynorth}"
DEPLOYMENT="bottega-aurora-infra"

for tool in az sqlcmd jq curl; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool"; exit 1; }
done

echo "== Signed-in user (becomes the SQL Entra admin)"
ADMIN_LOGIN=$(az ad signed-in-user show --query "mail || userPrincipalName" -o tsv)
ADMIN_ID=$(az ad signed-in-user show --query id -o tsv)
echo "$ADMIN_LOGIN"
echo "Subscription: $(az account show --query name -o tsv)"

echo "== Bicep deployment (takes several minutes)"
OUTPUTS=$(az deployment sub create \
  --name "$DEPLOYMENT" \
  --location "$LOCATION" \
  --template-file "$ROOT/infra/main.bicep" \
  --parameters location="$LOCATION" sqlAdminLogin="$ADMIN_LOGIN" sqlAdminObjectId="$ADMIN_ID" \
  --query properties.outputs -o json)
out() { jq -er ".$1.value" <<<"$OUTPUTS"; }

RG=$(out workloadResourceGroup)
SQL_SERVER=$(out sqlServerName)
SQL_FQDN=$(out sqlServerFqdn)
SHOP_ID=$(out shopIdentityName)
SHOP_CLIENT_ID=$(out shopIdentityClientId)

echo "== SQL firewall rule for this machine"
MY_IP=$(curl -fsS --max-time 10 https://api.ipify.org)
[[ -n "$MY_IP" ]] || { echo "Could not determine the public IP"; exit 1; }
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" -n deployer \
  --start-ip-address "$MY_IP" --end-ip-address "$MY_IP" -o none
echo "deployer -> $MY_IP"

sql() {
  sqlcmd -S "$SQL_FQDN" -d aurora --authentication-method ActiveDirectoryDefault -b "$@"
}

echo "== Waiting for the firewall rule to apply"
for attempt in $(seq 1 18); do
  if sql -Q "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" -eq 18 ]]; then
    echo "SQL still unreachable after 3 minutes"; exit 1
  fi
  sleep 10
done

echo "== Database user for $SHOP_ID (read and write rows only)"
# SID = the identity's client ID: no Microsoft Graph lookup needed.
sql -Q "
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$SHOP_ID')
BEGIN
    DECLARE @sid nvarchar(100) = CONVERT(nvarchar(100), CAST(CAST('$SHOP_CLIENT_ID' AS uniqueidentifier) AS varbinary(16)), 1);
    EXEC('CREATE USER [$SHOP_ID] WITH SID = ' + @sid + ', TYPE = E');
END
ALTER ROLE db_datareader ADD MEMBER [$SHOP_ID];
ALTER ROLE db_datawriter ADD MEMBER [$SHOP_ID];"

echo "== Migrations"
for migration in "$ROOT"/db/migrations/*.sql; do
  echo "$(basename "$migration")"
  sql -i "$migration"
done

echo
echo "== Done"
echo "Workload resource group:  $RG"
echo "Ops resource group:       $(out opsResourceGroup)"
echo "Web App:                  $(out webAppName)  ($(out webAppUrl))"
echo "SQL server:               $SQL_FQDN"
echo "Load generator job:       $(out loadgenJobName)"
echo "Deploy identity clientId: $(out deployIdentityClientId)"
echo "Tenant:                   $(az account show --query tenantId -o tsv)"
echo "Subscription:             $(az account show --query id -o tsv)"
echo "Agent role definition:    $(out agentRoleDefinitionId)"
