#!/usr/bin/env bash
# Creates (or updates) the Azure SRE Agent with the shop's configuration: subagent, incident response
# plan, hook, tool permissions, knowledge and code repository. Run after scripts/deploy-infra.sh.
# Usage: TEAMS_GROUP_ID=<team id> TEAMS_CHANNEL_ID=<channel id> scripts/deploy-agent.sh <owner>/<repo>
# Requires az, git, jq, python3 with PyYAML (used by the upstream templates).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITHUB_REPO="${1:?usage: deploy-agent.sh <owner>/<repo>}"
: "${TEAMS_GROUP_ID:?set TEAMS_GROUP_ID}" "${TEAMS_CHANNEL_ID:?set TEAMS_CHANNEL_ID}"
AGENT=aurora-agent
AGENT_RG=rg-aurora-agent
UPSTREAM_COMMIT=25a42306d298c4d28f11dd11ef9bb93cb0393be8
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/bottega-aurora/sre-agent-$UPSTREAM_COMMIT"
export SRE_AGENT_NO_TELEMETRY=1

echo "Subscription: $(az account show --query name -o tsv)"

echo "== Upstream templates (microsoft/sre-agent @ ${UPSTREAM_COMMIT:0:7}, tags patch applied)"
if [[ ! -d "$CACHE/sreagent-templates" ]]; then
  rm -rf "$CACHE"
  mkdir -p "$(dirname "$CACHE")"
  git clone -q --filter=blob:none --no-checkout https://github.com/microsoft/sre-agent "$CACHE"
  git -C "$CACHE" sparse-checkout set sreagent-templates
  git -C "$CACHE" checkout -q "$UPSTREAM_COMMIT"
  git -C "$CACHE" apply "$ROOT/sre-agent/vendor/sreagent-templates.tags.patch"
fi
TEMPLATES="$CACHE/sreagent-templates"

echo "== Rendering the configuration"
export GITHUB_REPO TEAMS_GROUP_ID TEAMS_CHANNEL_ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
WEB_APP_ID=$(az webapp list -g rg-aurora-prod --query "[0].id" -o tsv)
APP_INSIGHTS_ID=$(az resource list -g rg-aurora-prod --resource-type Microsoft.Insights/components --query "[0].id" -o tsv)
LOG_ANALYTICS_ID=$(az resource list -g rg-aurora-prod --resource-type Microsoft.OperationalInsights/workspaces --query "[0].id" -o tsv)
if [[ -z "$WEB_APP_ID" || -z "$APP_INSIGHTS_ID" || -z "$LOG_ANALYTICS_ID" ]]; then
  echo "Shop infrastructure not found: run scripts/deploy-infra.sh first"
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
    text = path.read_text()
    for name in names:
        text = text.replace("{{" + name + "}}", os.environ[name])
    left = re.findall(r"\{\{[A-Z_]+\}\}", text)
    if left:
        sys.exit(f"{path}: unresolved placeholders {left}")
    path.write_text(text)
PY

echo "== Agent deployment (two passes: on a new agent the response plan needs the subagent first)"
if ! (cd "$TEMPLATES" && ./bin/deploy.sh "$CONFIG"); then
  echo "First pass incomplete (expected on a new agent): running the second pass"
fi
(cd "$TEMPLATES" && ./bin/deploy.sh "$CONFIG" --force)

echo "== Slot swap role for the agent identity"
AGENT_PRINCIPAL=$(az identity list -g "$AGENT_RG" --query "[0].principalId" -o tsv)
az role assignment create --assignee-object-id "$AGENT_PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role "Aurora Agent Swap Operator" --scope "$(az group show -n rg-aurora-prod --query id -o tsv)" -o none
echo "Aurora Agent Swap Operator -> $AGENT_PRINCIPAL on rg-aurora-prod"

echo "== Tags on resources created by the platform (Smart Detection rules, action groups)"
for rg in rg-aurora-prod "$AGENT_RG"; do
  az resource list -g "$rg" --query "[?tags.category==null].id" -o tsv | while IFS= read -r id; do
    az tag update --resource-id "$id" --operation Merge --tags category=wpc-2026 -o none && echo "tagged ${id##*/}"
  done
done

echo "== Verification"
(cd "$TEMPLATES" && ./bin/verify-agent.sh "$SUBSCRIPTION_ID" "$AGENT_RG" "$AGENT" --expected "$CONFIG")

cat <<MANUAL

== Manual steps (OAuth: they need you in the browser, at https://sre.azure.com > $AGENT)
  1. Close the onboarding.
  2. Code access: connect $GITHUB_REPO with a fine-grained PAT limited to that repository
     (Contents, Pull requests, Issues: read and write; Metadata: read).
  3. Connectors > Microsoft Teams: sign in, set PostMessageToConversation and
     ReplyWithMessageToConversation to Allow, poster User, location Channel.
MANUAL
