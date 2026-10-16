#!/usr/bin/env bash
# Lets a GitHub repository deploy the shop of one environment: gives the deploy identity a federated
# credential for the repository's main branch and sets the repository variables used by the workflows.
# Federated credentials of previous repository copies are removed first (an identity holds at most 20).
# Idempotent. Usage: AURORA_ENV=<env> scripts/connect-repo.sh <owner>/<repo>
# (needs az and gh logged in, infrastructure deployed)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/aurora-env.sh
source "$ROOT/scripts/aurora-env.sh"
REPO="${1:?usage: AURORA_ENV=<env> connect-repo.sh <owner>/<repo>}"
echo "Subscription: $(az account show --query name -o tsv)"
echo "Environment:  $AURORA_ENV ($WORKLOAD_RG)"
# Subject exactly as GitHub issues it for this repository (immutable IDs or not, canonical case).
SUBJECT="$(gh api "repos/$REPO/actions/oidc/customization/sub" --jq .sub_claim_prefix):ref:refs/heads/main"
REPO_ID=$(gh api "repos/$REPO" --jq .id)
CREDENTIAL="github-$REPO_ID"
WEB_APP=$(az webapp list -g "$WORKLOAD_RG" --query '[0].name' -o tsv)
if [[ -z "$WEB_APP" ]]; then
  echo "No Web App in $WORKLOAD_RG: run scripts/deploy-infra.sh first"
  exit 1
fi

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  az identity federated-credential delete -g "$OPS_RG" --identity-name id-aurora-deploy --name "$name" --yes -o none
  echo "Removed federated credential $name (previous repository copy)"
done < <(az identity federated-credential list -g "$OPS_RG" --identity-name id-aurora-deploy \
  --query "[?starts_with(name, 'github-') && name != '$CREDENTIAL'].name" -o tsv)

az identity federated-credential create -g "$OPS_RG" --identity-name id-aurora-deploy \
  --name "$CREDENTIAL" \
  --issuer https://token.actions.githubusercontent.com \
  --subject "$SUBJECT" \
  --audiences api://AzureADTokenExchange -o none
echo "Federated credential: $SUBJECT"

gh variable set AZURE_CLIENT_ID --repo "$REPO" --body "$(az identity show -g "$OPS_RG" -n id-aurora-deploy --query clientId -o tsv)"
gh variable set AZURE_TENANT_ID --repo "$REPO" --body "$(az account show --query tenantId -o tsv)"
gh variable set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$(az account show --query id -o tsv)"
gh variable set RESOURCE_GROUP --repo "$REPO" --body "$WORKLOAD_RG"
gh variable set WEB_APP --repo "$REPO" --body "$WEB_APP"
gh variable list --repo "$REPO"
