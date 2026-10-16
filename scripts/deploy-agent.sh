#!/usr/bin/env bash
# Creates (or updates) the Azure SRE Agent with the shop's configuration: subagent, incident response
# plan, hook, tool permissions, knowledge and code repository. Run after scripts/deploy-infra.sh.
# Usage:
#   TEAMS_GROUP_ID=<team id> TEAMS_CHANNEL_ID=<channel id> AGENT_GITHUB_PAT=<token> scripts/deploy-agent.sh <owner>/<repo>
# AGENT_GITHUB_PAT: fine-grained token limited to <owner>/<repo> (Contents, Pull requests, Issues: read
# and write; Metadata: read). It is stored on the agent, which uses it to read code and open issues and PRs.
# Requires az, git, jq, python3 with PyYAML (used by the upstream templates).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITHUB_REPO="${1:?usage: deploy-agent.sh <owner>/<repo>}"
: "${TEAMS_GROUP_ID:?set TEAMS_GROUP_ID}" "${TEAMS_CHANNEL_ID:?set TEAMS_CHANNEL_ID}" "${AGENT_GITHUB_PAT:?set AGENT_GITHUB_PAT}"
AGENT=aurora-agent
AGENT_RG=rg-aurora-agent
UPSTREAM_COMMIT=25a42306d298c4d28f11dd11ef9bb93cb0393be8
PATCH="$ROOT/sre-agent/vendor/sreagent-templates.tags.patch"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/bottega-aurora/sre-agent-$UPSTREAM_COMMIT-$(shasum "$PATCH" | cut -c1-12)"
export SRE_AGENT_NO_TELEMETRY=1

echo "Subscription: $(az account show --query name -o tsv)"
if [[ "$(az group exists -n rg-aurora-prod)" != "true" ]]; then
  echo "Shop infrastructure not found: run scripts/deploy-infra.sh first"
  exit 1
fi

echo "== Upstream templates (microsoft/sre-agent @ ${UPSTREAM_COMMIT:0:7}, tags patch applied)"
if [[ ! -d "$CACHE/sreagent-templates" ]]; then
  # Build in a temporary folder and move it into place only when complete.
  STAGING="$(mktemp -d)/sre-agent"
  git clone -q --filter=blob:none --no-checkout https://github.com/microsoft/sre-agent "$STAGING"
  git -C "$STAGING" sparse-checkout set sreagent-templates
  git -C "$STAGING" checkout -q "$UPSTREAM_COMMIT"
  git -C "$STAGING" apply "$PATCH"
  mkdir -p "$(dirname "$CACHE")"
  mv "$STAGING" "$CACHE"
fi
TEMPLATES="$CACHE/sreagent-templates"

echo "== Rendering the configuration"
export GITHUB_REPO TEAMS_GROUP_ID TEAMS_CHANNEL_ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
WEB_APP_ID=$(az webapp list -g rg-aurora-prod --query "[0].id" -o tsv)
APP_INSIGHTS_ID=$(az resource list -g rg-aurora-prod --resource-type Microsoft.Insights/components --query "[0].id" -o tsv)
LOG_ANALYTICS_ID=$(az resource list -g rg-aurora-prod --resource-type Microsoft.OperationalInsights/workspaces --query "[0].id" -o tsv)
if [[ -z "$WEB_APP_ID" || -z "$APP_INSIGHTS_ID" || -z "$LOG_ANALYTICS_ID" ]]; then
  echo "Shop infrastructure incomplete: run scripts/deploy-infra.sh first"
  exit 1
fi
APP_INSIGHTS_APP_ID=$(az resource show --ids "$APP_INSIGHTS_ID" --query properties.AppId -o tsv)
export SUBSCRIPTION_ID WEB_APP_ID APP_INSIGHTS_ID APP_INSIGHTS_APP_ID LOG_ANALYTICS_ID

CONFIG=$(mktemp -d)
trap 'rm -rf "$CONFIG"' EXIT
cp -R "$ROOT/sre-agent/." "$CONFIG/"
rm -rf "$CONFIG/vendor"
python3 - "$CONFIG" <<'PY'
import os, pathlib, re, sys

names = ["SUBSCRIPTION_ID", "WEB_APP_ID", "APP_INSIGHTS_ID", "APP_INSIGHTS_APP_ID",
         "LOG_ANALYTICS_ID", "GITHUB_REPO", "TEAMS_GROUP_ID", "TEAMS_CHANNEL_ID"]
for path in pathlib.Path(sys.argv[1]).rglob("*"):
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    for name in names:
        text = text.replace("{{" + name + "}}", os.environ[name])
    left = re.findall(r"\{\{[A-Z_]+\}\}", text)
    if left:
        sys.exit(f"{path}: unresolved placeholders {left}")
    path.write_text(text, encoding="utf-8")
PY

echo "== Agent deployment (two passes: on a new agent the response plan needs the subagent first)"
# Only the dedicated token reaches the agent, never a GITHUB_PAT that happens to be in the shell.
(cd "$TEMPLATES" && GITHUB_PAT="$AGENT_GITHUB_PAT" ./bin/deploy.sh "$CONFIG")
(cd "$TEMPLATES" && GITHUB_PAT="$AGENT_GITHUB_PAT" ./bin/deploy.sh "$CONFIG" --force)

echo "== Slot swap role for the agent identity"
AGENT_PRINCIPAL=$(az identity list -g "$AGENT_RG" --query "[0].principalId" -o tsv)
az role assignment create --assignee-object-id "$AGENT_PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role "Aurora Agent Swap Operator" --scope "$(az group show -n rg-aurora-prod --query id -o tsv)" -o none
echo "Aurora Agent Swap Operator -> $AGENT_PRINCIPAL on rg-aurora-prod"

echo "== Tags on resources created by the platform (Smart Detection rules, action groups)"
for rg in rg-aurora-prod "$AGENT_RG"; do
  # IDs can contain spaces (e.g. "Failure Anomalies - ..."): read them line by line.
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if az tag update --resource-id "$id" --operation Merge --tags category=wpc-2026 -o none; then
      echo "tagged ${id##*/}"
    else
      echo "could not tag ${id##*/}"
    fi
  done < <(az resource list -g "$rg" --query "[?tags.category==null].id" -o tsv)
done

cat <<MANUAL

== Manual steps (they need you in the browser, at https://sre.azure.com > $AGENT)
  1. Close the onboarding.
  2. Connectors > Microsoft Teams: sign in, set PostMessageToConversation and
     ReplyWithMessageToConversation to Allow, poster User, location Channel.
MANUAL

echo
echo "== Verification"
if ! (cd "$TEMPLATES" && ./bin/verify-agent.sh "$SUBSCRIPTION_ID" "$AGENT_RG" "$AGENT" --expected "$CONFIG"); then
  echo "Verification reported differences: check the lines marked FAIL above."
  exit 1
fi
