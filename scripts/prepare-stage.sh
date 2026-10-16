#!/usr/bin/env bash
# Prepares a complete, clean environment for a rehearsal or for the stage, from nothing:
# repository copy, Azure infrastructure, 2.3.1 in production and 2.4.0 in staging, SRE Agent.
# Run scripts/destroy-infra.sh --yes first if resources from a previous run exist.
# Usage:
#   TEAMS_GROUP_ID=... TEAMS_CHANNEL_ID=... AGENT_GITHUB_PAT=... scripts/prepare-stage.sh <target owner/repo>
# The source repository is this checkout's GitHub repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: prepare-stage.sh <target owner/repo>}"
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
for rg in rg-aurora-prod rg-aurora-ops rg-aurora-agent; do
  if [[ "$(az group exists -n "$rg")" == "true" ]]; then
    echo "$rg still exists (or is being deleted): run scripts/destroy-infra.sh --yes and wait"
    exit 1
  fi
done

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
  local before out="" id=""
  before=$(gh run list -R "$TARGET" --workflow "$workflow" --limit 1 --json databaseId --jq '.[0].databaseId // 0' 2>/dev/null || echo 0)
  for _ in $(seq 1 24); do
    out=$(gh workflow run "$workflow" -R "$TARGET" "$@" 2>&1) && break
    out=""
    sleep 5
  done
  if [[ -z "$out" ]]; then
    echo "Could not dispatch $workflow on $TARGET"
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
  if ! gh run watch "$id" -R "$TARGET" --exit-status >/dev/null; then
    echo "$workflow $* failed: $(gh run view "$id" -R "$TARGET" --json url --jq .url)"
    exit 1
  fi
  echo "$workflow $* -> success"
}

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
    echo "The token still cannot write to $TARGET after 15 minutes: update its repository access and rerun deploy-agent.sh"
    exit 1
  fi
  [[ "$attempt" -eq 1 ]] && echo "Not yet: select $TARGET in the token's repository access on GitHub (checking every 15 s)"
  sleep 15
done

step "6/6 SRE Agent"
"$ROOT/scripts/deploy-agent.sh" "$TARGET"

echo
echo "== Prepared in $(( ($(date +%s) - START) / 60 )) minutes. After the two manual steps above, run:"
echo "   scripts/preflight.sh $TARGET"
