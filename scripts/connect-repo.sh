#!/usr/bin/env bash
# Lets a GitHub repository deploy the shop: adds a federated credential for its main branch to the
# deploy identity and sets the repository variables used by the workflows. Idempotent.
# Usage: scripts/connect-repo.sh <owner>/<repo>    (needs az and gh logged in, infrastructure deployed)
set -euo pipefail

REPO="${1:?usage: connect-repo.sh <owner>/<repo>}"
echo "Subscription: $(az account show --query name -o tsv)"
# Subject exactly as GitHub issues it for this repository (immutable IDs or not, canonical case).
SUBJECT="$(gh api "repos/$REPO/actions/oidc/customization/sub" --jq .sub_claim_prefix):ref:refs/heads/main"
REPO_ID=$(gh api "repos/$REPO" --jq .id)

az identity federated-credential create -g rg-aurora-ops --identity-name id-aurora-deploy \
  --name "github-$REPO_ID" \
  --issuer https://token.actions.githubusercontent.com \
  --subject "$SUBJECT" \
  --audiences api://AzureADTokenExchange -o none
echo "Federated credential: $SUBJECT"

gh variable set AZURE_CLIENT_ID --repo "$REPO" --body "$(az identity show -g rg-aurora-ops -n id-aurora-deploy --query clientId -o tsv)"
gh variable set AZURE_TENANT_ID --repo "$REPO" --body "$(az account show --query tenantId -o tsv)"
gh variable set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$(az account show --query id -o tsv)"
gh variable set WEB_APP --repo "$REPO" --body "$(az webapp list -g rg-aurora-prod --query '[0].name' -o tsv)"
gh variable list --repo "$REPO"
