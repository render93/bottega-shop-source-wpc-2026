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

step() { echo; echo "== $(date -u +%H:%M:%S) $*"; }

# Dispatches a workflow on the target repository and waits for that run to finish successfully.
run_workflow() {
  local workflow="$1"; shift
  local before id
  before=$(gh run list -R "$TARGET" --workflow "$workflow" --limit 1 --json databaseId --jq '.[0].databaseId // 0')
  for _ in $(seq 1 12); do
    gh workflow run "$workflow" -R "$TARGET" "$@" && break
    sleep 5   # right after the push GitHub may not list the workflow yet
  done
  for _ in $(seq 1 30); do
    id=$(gh run list -R "$TARGET" --workflow "$workflow" --limit 1 --json databaseId --jq '.[0].databaseId // 0')
    [[ "$id" != "$before" && "$id" != "0" ]] && break
    sleep 2
  done
  gh run watch "$id" -R "$TARGET" --exit-status >/dev/null
  echo "$workflow $* -> $(gh run view "$id" -R "$TARGET" --json conclusion --jq .conclusion)"
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
  perms=$(curl -s -H "Authorization: Bearer $AGENT_GITHUB_PAT" "https://api.github.com/repos/$TARGET" | jq -r '.permissions.push // false')
  [[ "$perms" == "true" ]] && { echo "Token has write access to $TARGET"; break; }
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
