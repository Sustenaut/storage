#!/usr/bin/env bash
# Copies every wheel attached to a release of the owners' public
# repositories (mirror/sources.json) into storage's wheels tenant, so an
# install can fall back to storage when GitHub's release downloads fail.
#
# A file here is named by its SHA-256, which is the hash a lock pins, so a
# lock line alone gives the fallback address:
#
#   https://github.com/<owner>/<repo>/releases/download/<tag>/<file>.whl --hash=sha256:<h>
#   https://storage.sustenaut.eu/wheels/f/<h>/<file>.whl
#
# Storage only has to be there, never trusted: pip and uv check the hash.
# A wheel already copied is skipped by a HEAD request, so a run copies only
# what is new. Run by .github/workflows/mirror.yml, which gives the job an
# OpenID Connect token; it needs gh, jq and curl. DRY_RUN=1 lists what it
# would copy, and needs no token.
set -euo pipefail

STORAGE="${STORAGE:-https://storage.sustenaut.eu}"
SOURCES="${SOURCES:-mirror/sources.json}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A fresh token for each upload: a backfill can outlast one.
token() {
  curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=storage.sustenaut.eu" | jq -r .value
}

there() { curl -fsI -o /dev/null "$STORAGE/wheels/f/$1/$2"; }

copied=0 skipped=0
while read -r owner; do
  while read -r repo; do
    while IFS=$'\t' read -r name digest url; do
      sha="${digest#sha256:}"
      if [[ "$sha" =~ ^[0-9a-f]{64}$ ]] && there "$sha" "$name"; then
        skipped=$((skipped + 1))
        continue
      fi
      curl -fsSL --retry 5 --retry-all-errors -o "$work/$name" "$url"
      actual="$(sha256sum "$work/$name" | cut -d' ' -f1)"
      if [[ -n "$digest" && "$sha" != "$actual" ]]; then
        echo "::error::$repo $name: GitHub says $digest, the download is sha256:$actual"
        exit 1
      fi
      if there "$actual" "$name"; then
        skipped=$((skipped + 1))
      elif [[ -n "${DRY_RUN:-}" ]]; then
        echo "would copy $repo $name ($actual)"
        copied=$((copied + 1))
      else
        id="$(curl -fsS --retry 3 --retry-all-errors -H "Authorization: Bearer $(token)" \
          -F "file=@$work/$name;filename=$name" "$STORAGE/wheels/files" | jq -r .id)"
        [[ "$id" == "$actual" ]] || { echo "::error::$repo $name: storage named it $id, not $actual"; exit 1; }
        echo "copied $repo $name ($actual)"
        copied=$((copied + 1))
      fi
      rm -f "$work/$name"
    done < <(gh api --paginate "repos/$repo/releases?per_page=100" \
      --jq '.[] | select(.draft | not) | .assets[] | select(.name | endswith(".whl")) | [.name, (.digest // ""), .browser_download_url] | @tsv')
  done < <(gh repo list "$owner" --visibility public --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner')
done < <(jq -r '.wheels.owners[]' "$SOURCES")

echo "$copied copied, $skipped already there"
