#!/usr/bin/env bash
# Deploys a zip package to a slot of the shop and waits until the slot serves that version.
# Usage: scripts/ci/deploy-slot.sh <production|staging> <zip> <version>   (needs RESOURCE_GROUP, WEB_APP)
set -euo pipefail

SLOT="$1"
ZIP="$2"
VERSION="$3"
: "${RESOURCE_GROUP:?}" "${WEB_APP:?}"

args=()
[[ "$SLOT" == production ]] || args=(--slot "$SLOT")

# --clean: files left by a previous build can keep the app from starting.
az webapp deploy -g "$RESOURCE_GROUP" -n "$WEB_APP" "${args[@]}" --src-path "$ZIP" --type zip --clean true

host=$(az webapp show -g "$RESOURCE_GROUP" -n "$WEB_APP" "${args[@]}" --query defaultHostName -o tsv)
for _ in $(seq 1 30); do
  body=$(curl -s -m 15 "https://$host/api/version" || true)
  echo "$SLOT: $body"
  if [[ "$body" == *"\"$VERSION\""* ]]; then
    exit 0
  fi
  sleep 10
done
echo "The $SLOT slot is not serving $VERSION"
exit 1
