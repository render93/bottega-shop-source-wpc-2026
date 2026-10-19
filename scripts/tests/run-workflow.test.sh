#!/usr/bin/env bash
# Tests scripts/lib/run-workflow.sh with a stubbed gh and a fake clock (no network, no waiting).
# Usage: bash scripts/tests/run-workflow.test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILURES=0

expect() { # <label> <needle> <haystack>
  if grep -qF -- "$2" <<<"$3"; then echo "ok   $1"; else echo "FAIL $1: missing '$2'"; echo "$3" | sed 's/^/     /'; FAILURES=1; fi
}
expect_absent() { # <label> <needle> <haystack>
  if grep -qF -- "$2" <<<"$3"; then echo "FAIL $1: unexpected '$2'"; echo "$3" | sed 's/^/     /'; FAILURES=1; else echo "ok   $1"; fi
}

# Stubbed gh: the run is in progress for the first 8 views, then ends with $CONCLUSION.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "run list") echo 100 ;;
  "workflow run") echo "https://github.com/x/y/actions/runs/101" ;;
  "run view")
    n=$(cat "$WORK/views" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$WORK/views"
    if [[ "$*" == *url* ]]; then echo "https://github.com/x/y/actions/runs/101"
    elif [[ "$n" -lt 9 ]]; then echo "in_progress "
    else echo "completed $CONCLUSION"; fi ;;
esac
STUB
chmod +x "$WORK/bin/gh"

run_case() { # <conclusion>: runs run_workflow in a subshell, prints its output and exit code
  rm -f "$WORK/views"
  (
    export WORK CONCLUSION="$1" PATH="$WORK/bin:$PATH"
    TARGET=owner/repo
    FAKE=0
    sleep() { FAKE=$((FAKE + 10)); }
    date() { if [[ "${1:-}" == +%s ]]; then echo $((1000 + FAKE)); else command date "$@"; fi; }
    # shellcheck source=scripts/lib/run-workflow.sh
    source "$ROOT/scripts/lib/run-workflow.sh"
    run_workflow deploy-version.yml -f ref=v2.3.1 -f slot=production
  ) 2>&1 && echo "exit=0" || echo "exit=$?"
}

out=$(run_case success)
expect "announces what it waits for" "Waiting for deploy-version.yml -f ref=v2.3.1 -f slot=production: https://github.com/owner/repo/actions/runs/101" "$out"
expect "prints progress" "in_progress, 0m30s elapsed" "$out"
expect "prints progress again after 30 s" "in_progress, 1m00s elapsed" "$out"
expect_absent "throttles progress (no 10 s line)" "0m10s elapsed" "$out"
expect_absent "throttles progress (no 20 s line)" "0m20s elapsed" "$out"
expect "reports success" "deploy-version.yml -f ref=v2.3.1 -f slot=production -> success" "$out"
expect "exits 0 on success" "exit=0" "$out"

out=$(run_case failure)
expect "reports the failure with the run URL" "ended with failure: https://github.com/x/y/actions/runs/101" "$out"
expect "exits non-zero on failure" "exit=1" "$out"

exit "$FAILURES"
