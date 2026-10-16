#!/usr/bin/env bash
# Publishes a fresh public copy of a repository: main and the tags with their full history, no issues,
# pull requests or workflow runs. An existing target is deleted first (needs the gh scope delete_repo).
# Usage: scripts/copy-repo.sh <source owner/repo> <target owner/repo>
set -euo pipefail

SOURCE="${1:?usage: copy-repo.sh <source owner/repo> <target owner/repo>}"
TARGET="${2:?usage: copy-repo.sh <source owner/repo> <target owner/repo>}"
if [[ "$SOURCE" == "$TARGET" ]]; then
  echo "Source and target must differ"
  exit 1
fi

if gh repo view "$TARGET" >/dev/null 2>&1; then
  if ! gh auth status 2>&1 | grep -q delete_repo; then
    echo "$TARGET exists and gh cannot delete repositories: run gh auth refresh -h github.com -s delete_repo"
    exit 1
  fi
  echo "== Deleting the previous $TARGET"
  gh repo delete "$TARGET" --yes
fi

echo "== Creating $TARGET"
DESCRIPTION=$(gh repo view "$SOURCE" --json description --jq .description)
for attempt in 1 2 3 4 5 6; do
  # Right after a delete GitHub can still report the name as taken.
  gh repo create "$TARGET" --public --description "$DESCRIPTION" && break
  [[ "$attempt" -eq 6 ]] && exit 1
  sleep 10
done

# Actions stay off while the history is pushed: a push to main would otherwise deploy and swap.
gh api -X PUT "repos/$TARGET/actions/permissions" -F enabled=false

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone -q --bare "https://github.com/$SOURCE.git" "$WORK/source.git"
# gh credentials (with the workflow scope) for the push, never an interactive prompt.
GIT_TERMINAL_PROMPT=0 git -C "$WORK/source.git" -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
  push -q "https://github.com/$TARGET.git" refs/heads/main:refs/heads/main 'refs/tags/*:refs/tags/*'

gh api -X PUT "repos/$TARGET/actions/permissions" -F enabled=true -f allowed_actions=all

EXPECTED_WORKFLOWS=$(gh api "repos/$SOURCE/contents/.github/workflows" --jq length)
for attempt in $(seq 1 30); do
  registered=$(gh api "repos/$TARGET/actions/workflows" --jq .total_count)
  [[ "$registered" -ge "$EXPECTED_WORKFLOWS" ]] && break
  if [[ "$attempt" -eq 30 ]]; then
    echo "Only $registered of $EXPECTED_WORKFLOWS workflows registered on $TARGET"
    exit 1
  fi
  sleep 2
done

# Changes to main only through pull requests (no review required), administrators included.
gh api -X PUT "repos/$TARGET/branches/main/protection" --input - >/dev/null <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null
}
JSON

echo "Copied $SOURCE -> $TARGET (main $(gh api "repos/$TARGET/commits/main" --jq .sha | cut -c1-7), tags: $(gh api "repos/$TARGET/tags" --jq '[.[].name] | join(", ")'))"
