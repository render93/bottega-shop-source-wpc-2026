#!/usr/bin/env bash
# Prepares a complete, clean environment for a rehearsal or for the stage, from nothing:
# repository copy, Azure infrastructure, 2.3.1 in production and 2.4.0 in staging, SRE Agent.
# The environment name must be new: metrics and alert history are tied to the resource IDs, and the
# agent would read a previous run's incidents as its own. One environment at a time: any other
# environment must be destroyed first. The shared rg-aurora-ops may exist.
# Usage:
#   TEAMS_GROUP_ID=... TEAMS_CHANNEL_ID=... AGENT_GITHUB_PAT=... scripts/prepare-stage.sh <env> <target owner/repo>
# <env>: 1-8 lowercase letters or digits. The source repository is this checkout's GitHub repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="usage: prepare-stage.sh <env> <target owner/repo>"
AURORA_ENV="${1:?$USAGE}"
TARGET="${2:?$USAGE}"
export AURORA_ENV
# shellcheck source=scripts/aurora-env.sh
source "$ROOT/scripts/aurora-env.sh"
: "${TEAMS_GROUP_ID:?set TEAMS_GROUP_ID}" "${TEAMS_CHANNEL_ID:?set TEAMS_CHANNEL_ID}" "${AGENT_GITHUB_PAT:?set AGENT_GITHUB_PAT}"
SOURCE=$(cd "$ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner)
START=$(date +%s)

# Infrastructure and agent configuration come from this checkout, the copy from the remote main:
# they must be the same commit.
git -C "$ROOT" fetch -q origin main
if [[ -n "$(git -C "$ROOT" status --porcelain)" || "$(git -C "$ROOT" rev-parse HEAD)" != "$(git -C "$ROOT" rev-parse origin/main)" ]]; then
  echo "This checkout must be a clean copy of origin/main (git checkout main && git pull)"
  exit 1
fi
for rg in "$OPS_RG" "$WORKLOAD_RG" "$AGENT_RG"; do
  if [[ "$(az group show -n "$rg" --query properties.provisioningState -o tsv 2>/dev/null || true)" == "Deleting" ]]; then
    echo "$rg is being deleted: wait until the deletion completes (az group wait -n $rg --deleted)"
    exit 1
  fi
done
# One environment at a time: resource names inside the groups are the same in every environment.
OTHER_ENVS=$(az group list --query "[?starts_with(name,'rg-aurora-prod-') || starts_with(name,'rg-aurora-agent-')].name" -o tsv)
if [[ -n "$OTHER_ENVS" ]]; then
  echo "Another environment exists: $(echo "$OTHER_ENVS" | tr '\n' ' ')"
  echo "Remove it first: AURORA_ENV=<its env> scripts/destroy-infra.sh --yes"
  exit 1
fi
NAME_USED="environment name already used: pick a new one (metrics and alert history of its resources would be visible to the agent)"
# Deployment history outlives the 30-day alert window below.
if az deployment sub show -n "bottega-aurora-infra-$AURORA_ENV" -o none 2>/dev/null; then
  echo "$NAME_USED"
  echo "(deployment bottega-aurora-infra-$AURORA_ENV exists in the subscription)"
  exit 1
fi
# Alerts of the last 30 days (fired or resolved, all pages) whose rule lives in this environment's workload group.
url="https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&timeRange=30d&pageCount=250"
PAST_ALERTS=0
while [[ -n "$url" ]]; do
  page=$(az rest --method get --url "$url" -o json)
  PAST_ALERTS=$(( PAST_ALERTS + $(jq --arg rg "/resourcegroups/$WORKLOAD_RG/" \
    '[.value[]? | select((.properties.essentials.alertRule // "") | ascii_downcase | contains($rg))] | length' <<<"$page") ))
  url=$(jq -r '.nextLink // empty' <<<"$page")
done
if [[ "$PAST_ALERTS" -gt 0 ]]; then
  echo "$NAME_USED"
  echo "($PAST_ALERTS alerts on $WORKLOAD_RG in the last 30 days)"
  exit 1
fi

# True when the token can write to the target: an empty label is rejected with 422 when the token
# has access, 403 when it does not. Nothing is created. The header is passed on stdin, not in argv.
pat_can_write() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H @- -H 'Content-Type: application/json' -d '{}' \
    "https://api.github.com/repos/$TARGET/labels" <<<"Authorization: Bearer $AGENT_GITHUB_PAT" || true)
  [[ "$code" == "422" ]]
}

step() { echo; echo "== $(date -u +%H:%M:%S) $*"; }

# Dispatches a workflow on the target repository and waits for that run to finish successfully.
run_workflow() {
  local workflow="$1"; shift
  local before out="" id="" error="" status="" conclusion="" state
  before=$(gh run list -R "$TARGET" --workflow "$workflow" --limit 1 --json databaseId --jq '.[0].databaseId // 0' 2>/dev/null || echo 0)
  for _ in $(seq 1 24); do
    out=$(gh workflow run "$workflow" -R "$TARGET" "$@" 2>&1) && break
    error="$out"
    out=""
    sleep 5
  done
  if [[ -z "$out" ]]; then
    echo "Could not dispatch $workflow on $TARGET: $error"
    exit 1
  fi
  # gh prints the URL of the created run when it can; otherwise wait for a new run to appear.
  id=$(grep -oE 'actions/runs/[0-9]+' <<<"$out" | grep -oE '[0-9]+$' || true)
  if [[ -z "$id" ]]; then
    for _ in $(seq 1 30); do
      id=$(gh run list -R "$TARGET" --workflow "$workflow" --limit 1 --json databaseId --jq '.[0].databaseId // 0' 2>/dev/null || echo 0)
      [[ "$id" != "$before" && "$id" != "0" ]] && break
      id=""
      sleep 2
    done
  fi
  if [[ -z "$id" ]]; then
    echo "No run of $workflow appeared on $TARGET"
    exit 1
  fi
  # Poll the run status (gh run watch fails on a run whose jobs do not exist yet); API errors are retried.
  local deadline view_failed=false
  deadline=$(( $(date +%s) + 1800 ))
  while [[ "$status" != "completed" && "$(date +%s)" -lt "$deadline" ]]; do
    sleep 10
    if ! state=$(gh run view "$id" -R "$TARGET" --json status,conclusion --jq '.status + " " + .conclusion' 2>/dev/null); then
      if [[ "$view_failed" == false ]]; then
        echo "gh run view $id failed: retrying every 10 s"
        view_failed=true
      fi
      continue
    fi
    status="${state%% *}"
    conclusion="${state#* }"
  done
  if [[ "$status" != "completed" ]]; then
    echo "$workflow $* still ${status:-unknown} after about 30 minutes: $(gh run view "$id" -R "$TARGET" --json url --jq .url 2>/dev/null || echo "run $id")"
    exit 1
  fi
  if [[ "$conclusion" != "success" ]]; then
    echo "$workflow $* ended with ${conclusion:-no conclusion}: $(gh run view "$id" -R "$TARGET" --json url --jq .url 2>/dev/null || echo "run $id")"
    exit 1
  fi
  echo "$workflow $* -> success"
}

echo "Environment: $AURORA_ENV ($WORKLOAD_RG, agent in $AGENT_RG, shared $OPS_RG)"

step "1/6 Repository copy $SOURCE -> $TARGET"
"$ROOT/scripts/copy-repo.sh" "$SOURCE" "$TARGET"
cat <<NOTE

   >>> Now, while the infrastructure deploys: on GitHub, edit the fine-grained token in
   >>> AGENT_GITHUB_PAT and select $TARGET under "Repository access" (the copy is a new repository).
NOTE

step "2/6 Azure infrastructure"
"$ROOT/scripts/deploy-infra.sh"

step "3/6 Connect $TARGET to Azure"
"$ROOT/scripts/connect-repo.sh" "$TARGET"

step "4/6 2.3.1 in production, 2.4.0 in staging"
run_workflow deploy-version.yml -f ref=v2.3.1 -f slot=production
run_workflow deploy-version.yml -f ref=v2.4.0 -f slot=staging

step "5/6 Waiting until AGENT_GITHUB_PAT can open issues on $TARGET"
for attempt in $(seq 1 60); do
  if pat_can_write; then
    echo "Token has write access to $TARGET"
    break
  fi
  if [[ "$attempt" -eq 60 ]]; then
    echo "The token still cannot write to $TARGET after 15 minutes: update its repository access and rerun:"
    echo "   AURORA_ENV=$AURORA_ENV TEAMS_GROUP_ID=... TEAMS_CHANNEL_ID=... AGENT_GITHUB_PAT=... scripts/deploy-agent.sh $TARGET"
    exit 1
  fi
  [[ "$attempt" -eq 1 ]] && echo "Not yet: select $TARGET in the token's repository access on GitHub (checking every 15 s)"
  sleep 15
done

step "6/6 SRE Agent"
"$ROOT/scripts/deploy-agent.sh" "$TARGET"

echo
echo "== Prepared in $(( ($(date +%s) - START) / 60 )) minutes. After the two manual steps above, run:"
echo "   AURORA_ENV=$AURORA_ENV scripts/preflight.sh $TARGET"
