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
  echo "== Deleting the previous $TARGET"
  gh repo delete "$TARGET" --yes
fi

echo "== Creating $TARGET"
gh repo create "$TARGET" --public --description "$(gh repo view "$SOURCE" --json description --jq .description)"

# Actions stay off while the history is pushed: a push to main would otherwise deploy and swap.
gh api -X PUT "repos/$TARGET/actions/permissions" -F enabled=false

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone -q --bare "https://github.com/$SOURCE.git" "$WORK/source.git"
git -C "$WORK/source.git" push -q "https://github.com/$TARGET.git" refs/heads/main:refs/heads/main 'refs/tags/*:refs/tags/*'

gh api -X PUT "repos/$TARGET/actions/permissions" -F enabled=true -f allowed_actions=all

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
