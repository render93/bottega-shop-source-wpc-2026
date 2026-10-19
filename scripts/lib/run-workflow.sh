#!/usr/bin/env bash
# Sourced, not run: run_workflow <workflow file> [gh workflow run flags...]
# Dispatches the workflow on $TARGET (owner/repo), prints the run URL, then the run status and the
# elapsed time every 30 s, and returns 0 only when the run succeeds. Exits 1 with the run URL otherwise.
# Polls with gh run view: gh run watch fails on a run whose jobs do not exist yet.

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
  echo "Waiting for $workflow $*: https://github.com/$TARGET/actions/runs/$id"
  local started deadline view_failed=false last_print=0 elapsed
  started=$(date +%s)
  deadline=$(( started + 1800 ))
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
    elapsed=$(( $(date +%s) - started ))
    if [[ "$status" != "completed" && $(( elapsed - last_print )) -ge 30 ]]; then
      printf '  %s, %dm%02ds elapsed\n' "$status" $(( elapsed / 60 )) $(( elapsed % 60 ))
      last_print=$elapsed
    fi
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
