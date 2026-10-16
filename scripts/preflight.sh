#!/usr/bin/env bash
# Read-only check of a prepared environment: one OK/FAIL line per item, exit 1 if anything fails.
# Usage: scripts/preflight.sh <target owner/repo>
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: preflight.sh <target owner/repo>}"
SOURCE=$(cd "$ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner)
FAILED=0

# GitHub API value, or nothing when the call fails (e.g. 404 on a repository not created yet).
api() { local out; out=$(gh api "$@" 2>/dev/null) && echo "$out"; }

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ -n "$actual" && "$actual" == "$expected" ]]; then
    echo "OK    $label: $actual"
  else
    echo "FAIL  $label: expected $expected, got ${actual:-nothing}"
    FAILED=1
  fi
}

echo "== Azure ($(az account show --query name -o tsv))"
for rg in rg-aurora-prod rg-aurora-ops rg-aurora-agent; do
  check "resource group $rg" true "$(az group exists -n "$rg")"
done
WEB_APP=$(az webapp list -g rg-aurora-prod --query "[0].name" -o tsv 2>/dev/null)
for slot in production staging; do
  args=(); [[ "$slot" == production ]] || args=(--slot "$slot")
  # ${args[@]+...}: bash 3.2 treats an empty array as unset under set -u.
  host=$(az webapp show -g rg-aurora-prod -n "$WEB_APP" ${args[@]+"${args[@]}"} --query defaultHostName -o tsv 2>/dev/null)
  expected=2.3.1; [[ "$slot" == staging ]] && expected=2.4.0
  check "$slot version" "$expected" "$(curl -s -m 15 "https://$host/api/version" | jq -r .version 2>/dev/null)"
done
PROD_HOST=$(az webapp show -g rg-aurora-prod -n "$WEB_APP" --query defaultHostName -o tsv 2>/dev/null)
LIVE=$(curl -s -m 15 "https://$PROD_HOST/api/live")
check "failed checkouts in the last minute" 0 "$(jq -r .failedLastMinute <<<"$LIVE" 2>/dev/null)"
check "lost today" 0 "$(jq -r '.lostToday | floor' <<<"$LIVE" 2>/dev/null)"
echo "INFO  orders in the last minute: $(jq -r .ordersLastMinute <<<"$LIVE" 2>/dev/null) (about 180 with the traffic on)"
FIRED=$(az rest --method get --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&targetResourceGroup=rg-aurora-prod&monitorCondition=Fired&timeRange=1d" \
  --query "length(value[?contains(properties.essentials.alertRule, 'alert-checkout-5xx')])" -o tsv 2>/dev/null)
check "fired 5xx alerts" 0 "$FIRED"
ROLE=$(az role assignment list --scope "$(az group show -n rg-aurora-prod --query id -o tsv 2>/dev/null)" \
  --query "length([?roleDefinitionName=='Aurora Agent Swap Operator'])" -o tsv 2>/dev/null)
check "agent swap role assignments" 1 "$ROLE"

echo "== SRE Agent"
UPSTREAM_COMMIT=25a42306d298c4d28f11dd11ef9bb93cb0393be8
PATCH="$ROOT/sre-agent/vendor/sreagent-templates.tags.patch"
TEMPLATES="${XDG_CACHE_HOME:-$HOME/.cache}/bottega-aurora/sre-agent-$UPSTREAM_COMMIT-$(shasum "$PATCH" | cut -c1-12)/sreagent-templates"
if [[ -d "$TEMPLATES" ]]; then
  VERIFY=$(cd "$TEMPLATES" && SRE_AGENT_NO_TELEMETRY=1 ./bin/verify-agent.sh "$(az account show --query id -o tsv)" rg-aurora-agent aurora-agent --expected "$ROOT/sre-agent" 2>&1)
  check "agent configuration" "0 failed" "$(grep -oE '[0-9]+ failed' <<<"$VERIFY")"
  check "Teams connector" true "$(grep -E 'Managed connector names' <<<"$VERIFY" | grep -qi teams && echo true || echo false)"
else
  check "agent templates in cache" present missing
fi

echo "== GitHub ($TARGET)"
check "main identical to $SOURCE" "$(api "repos/$SOURCE/commits/main" --jq .sha)" "$(api "repos/$TARGET/commits/main" --jq .sha)"
for tag in v2.3.1 v2.4.0; do
  check "tag $tag" "$(api "repos/$SOURCE/git/ref/tags/$tag" --jq .object.sha)" "$(api "repos/$TARGET/git/ref/tags/$tag" --jq .object.sha)"
done
check "issues and pull requests" 0 "$(api "repos/$TARGET/issues?state=all&per_page=1" --jq length)"
check "main requires pull requests (admins included)" true "$(api "repos/$TARGET/branches/main/protection" --jq '.enforce_admins.enabled and (.required_pull_request_reviews != null)')"
check "Actions enabled" true "$(api "repos/$TARGET/actions/permissions" --jq .enabled)"
check "repository variables" 4 "$(gh variable list -R "$TARGET" --json name --jq '[.[] | select(.name | IN("AZURE_CLIENT_ID","AZURE_TENANT_ID","AZURE_SUBSCRIPTION_ID","WEB_APP"))] | length' 2>/dev/null)"

if [[ -n "${AGENT_GITHUB_PAT:-}" ]]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H @- -H 'Content-Type: application/json' -d '{}' \
    "https://api.github.com/repos/$TARGET/labels" <<<"Authorization: Bearer $AGENT_GITHUB_PAT")
  check "agent token can write to $TARGET (422 = yes, 403 = no)" 422 "$code"
else
  echo "INFO  agent token not checked (AGENT_GITHUB_PAT not set)"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then echo "PREFLIGHT: all green"; else echo "PREFLIGHT: something is red"; fi
exit "$FAILED"
