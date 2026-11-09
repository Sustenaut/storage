#!/usr/bin/env bash
# Fetches the lock files of every repository the mirror may read into
# $LOCKS/<owner>/<repo>/<path>: each .terraform.lock.hcl and each
# requirements*.lock, at its default branch. mirror/terraform.sh and
# mirror/pypi.sh then copy what they pin.
#
# With the mirror app's token (GH_TOKEN from the sustenaut-storage-mirror
# app, contents: read), the repositories are the ones its installation
# reaches, private ones included. Without it (MIRROR_APP unset), they are
# the public repositories of the owners in mirror/sources.json.
set -euo pipefail

SOURCES="${SOURCES:-mirror/sources.json}"
LOCKS="${LOCKS:?LOCKS names the directory the lock files go to}"
mkdir -p "$LOCKS"

if [[ -n "${MIRROR_APP:-}" ]]; then
  repos="$(gh api --paginate /installation/repositories --jq '.repositories[] | select(.archived | not) | .full_name')"
else
  repos="$(jq -r '.wheels.owners[]' "$SOURCES" | while read -r owner; do
    gh repo list "$owner" --visibility public --no-archived --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner'
  done)"
fi

count=0
for repo in $repos; do
  while read -r path; do
    [[ -n "$path" ]] || continue
    mkdir -p "$LOCKS/$repo/$(dirname "$path")"
    gh api -H "Accept: application/vnd.github.raw+json" "repos/$repo/contents/$path" > "$LOCKS/$repo/$path"
    count=$((count + 1))
  done < <(gh api "repos/$repo/git/trees/HEAD?recursive=1" \
    --jq '.tree[] | select(.type == "blob") | .path | select(test("(^|/)(\\.terraform\\.lock\\.hcl|requirements[^/]*\\.lock)$"))' 2>/dev/null || true)
done
echo "$count lock files from $(wc -w <<<"$repos") repositories"
