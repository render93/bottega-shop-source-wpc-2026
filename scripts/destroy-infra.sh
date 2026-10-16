#!/usr/bin/env bash
# Deletes the Bottega Aurora resource groups to stop the costs. Without --yes it only lists
# what would be deleted. The custom agent role (free) and the agent's own resource group are kept.
set -euo pipefail

echo "Subscription: $(az account show --query name -o tsv)"

RESOURCE_GROUPS=(rg-aurora-prod rg-aurora-ops)

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

if [[ ${#existing[@]} -eq 0 ]]; then
  echo "Nothing to delete."
  exit 0
fi

if [[ "${1:-}" != "--yes" ]]; then
  echo
  echo "Dry run. Run again with --yes to delete: ${existing[*]}"
  exit 0
fi

# Purge the Log Analytics workspace first: a plain resource group delete only soft-deletes it,
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
for rg in "${existing[@]}"; do
  az group wait -n "$rg" --deleted --timeout 3600
  echo "$rg deleted"
done
