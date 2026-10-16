#!/usr/bin/env bash
# Sourced by the other scripts, not run directly: validates AURORA_ENV, the environment name, and
# derives the resource group names. Workload and agent groups are per environment (metrics and alert
# history are tied to resource IDs, so a new name starts clean); rg-aurora-ops is shared.
# shellcheck disable=SC2034
ENV_PATTERN='^[a-z0-9]{1,8}$'
if [[ ! "${AURORA_ENV:-}" =~ $ENV_PATTERN ]]; then
  echo "Set AURORA_ENV to the environment name: 1-8 lowercase letters or digits (e.g. AURORA_ENV=dev1)" >&2
  exit 1
fi
WORKLOAD_RG="rg-aurora-prod-$AURORA_ENV"
AGENT_RG="rg-aurora-agent-$AURORA_ENV"
OPS_RG="rg-aurora-ops"
