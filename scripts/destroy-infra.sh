#!/usr/bin/env bash
# Deletes the resource groups of one environment (workload and agent) to stop the costs. The shared
# rg-aurora-ops (deploy identity, load generator: no cost at rest) is kept unless --all is given.
# Without --yes it only lists what would be deleted. The custom agent role (free) is always kept.
# Usage: AURORA_ENV=<env> scripts/destroy-infra.sh [--yes] [--all]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/aurora-env.sh
source "$ROOT/scripts/aurora-env.sh"

CONFIRMED=false
ALL=false
for arg in "$@"; do
  case "$arg" in
    --yes) CONFIRMED=true ;;
    --all) ALL=true ;;
    *) echo "usage: AURORA_ENV=<env> destroy-infra.sh [--yes] [--all]"; exit 1 ;;
  esac
done

echo "Subscription: $(az account show --query name -o tsv)"
echo "Environment:  $AURORA_ENV"

RESOURCE_GROUPS=("$WORKLOAD_RG" "$AGENT_RG")
if [[ "$ALL" == true ]]; then
  RESOURCE_GROUPS+=("$OPS_RG")
fi

existing=()
for rg in "${RESOURCE_GROUPS[@]}"; do
  if [[ "$(az group exists -n "$rg")" == "true" ]]; then
    existing+=("$rg")
    echo "== $rg"
    az resource list -g "$rg" --query "[].{name:name, type:type}" -o table
  else
    echo "== $rg: not found"
  fi
done
[[ "$ALL" == true ]] || echo "== $OPS_RG: kept (shared by all environments; --all deletes it too)"

if [[ ${#existing[@]} -eq 0 ]]; then
  echo "Nothing to delete."
  exit 0
fi

if [[ "$CONFIRMED" != true ]]; then
  echo
  echo "Dry run. Run again with --yes to delete: ${existing[*]}"
  exit 0
fi

# Delete the SRE Agent first and on its own: a resource group delete may remove its identity, workspace and
# Application Insights before the agent, and on 01/11/2026 the agent deletion then failed and blocked the group.
for rg in "${existing[@]}"; do
  agents=$(az resource list -g "$rg" --resource-type Microsoft.App/agents --query "[].id" -o tsv)
  for agent in $agents; do
    echo "Deleting SRE Agent ${agent##*/} in $rg (a few minutes)..."
    if ! az resource delete --ids "$agent" -o none; then
      echo "FAILED: the SRE Agent could not be deleted, nothing else was touched."
      echo "Retry later, or open a support ticket with the operation ID above for: $agent"
      exit 1
    fi
  done
done

# Purge the Log Analytics workspace next: a plain resource group delete only soft-deletes it,
# and the next deploy would recover it with the previous runs' telemetry.
for rg in "${existing[@]}"; do
  workspaces=$(az monitor log-analytics workspace list -g "$rg" --query "[].name" -o tsv)
  for ws in $workspaces; do
    echo "Purging Log Analytics workspace $ws..."
    az monitor log-analytics workspace delete -g "$rg" -n "$ws" --force true --yes
  done
done

for rg in "${existing[@]}"; do
  echo "Deleting $rg..."
  az group delete -n "$rg" --yes --no-wait
done
# Wait for each group, saying what it is waiting for; a group that leaves the Deleting state while it still
# exists means the deletion failed.
for rg in "${existing[@]}"; do
  waited=0
  while [[ "$(az group exists -n "$rg")" == "true" ]]; do
    state=$(az group show -n "$rg" --query properties.provisioningState -o tsv 2>/dev/null || true)
    if [[ -n "$state" && "$state" != "Deleting" ]]; then
      echo "FAILED: deletion of $rg stopped (state $state). Resources left:"
      az resource list -g "$rg" --query "[].{name:name, type:type}" -o table
      echo "Activity log of the group: az monitor activity-log list -g $rg --offset 2h --status Failed -o table"
      exit 1
    fi
    if (( waited >= 3600 )); then
      echo "FAILED: $rg still deleting after 60 minutes"
      exit 1
    fi
    (( waited % 120 == 0 )) && echo "  waiting for $rg to be deleted ($((waited / 60)) min)"
    sleep 30
    waited=$((waited + 30))
  done
  echo "$rg deleted"
done
