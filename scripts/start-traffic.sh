#!/usr/bin/env bash
# Starts the k6 load generator (unless it is already running) and waits until orders reach the live counter.
set -euo pipefail

active=$(az containerapp job execution list -g rg-aurora-ops -n job-aurora-loadgen \
  --query "length([?properties.status=='Running' || properties.status=='Processing'])" -o tsv)
if [[ "$active" -gt 0 ]]; then
  echo "The load generator is already running."
else
  az containerapp job start -g rg-aurora-ops -n job-aurora-loadgen -o none
  echo "k6 started at $(date -u +%H:%M:%S) UTC"
fi
WEB_APP=$(az webapp list -g rg-aurora-prod --query "[0].name" -o tsv)
HOST=$(az webapp show -g rg-aurora-prod -n "$WEB_APP" --query defaultHostName -o tsv)
for _ in $(seq 1 12); do
  orders=$(curl -s -m 10 "https://$HOST/api/live" | jq -r '.ordersLastMinute // 0' 2>/dev/null || echo 0)
  if [[ "$orders" -gt 0 ]]; then
    echo "Orders are flowing: $orders in the last minute (about 180 at full rate after one minute)"
    exit 0
  fi
  sleep 10
done
echo "No orders after 2 minutes: check the job execution in the portal"
exit 1
