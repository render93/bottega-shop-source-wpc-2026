#!/usr/bin/env bash
# Stops every running execution of the k6 load generator.
set -euo pipefail

running=$(az containerapp job execution list -g rg-aurora-ops -n job-aurora-loadgen --query "[?properties.status=='Running' || properties.status=='Processing'].name" -o tsv)
if [[ -z "$running" ]]; then
  echo "No running executions."
  exit 0
fi
for execution in $running; do
  az containerapp job stop -g rg-aurora-ops -n job-aurora-loadgen --job-execution-name "$execution" -o none
  echo "Stopped $execution"
done
