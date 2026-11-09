#!/usr/bin/env bash
# Copies the Terraform providers in mirror/sources.json into storage's
# terraform tenant, which serves them by Terraform's provider network mirror
# protocol, so an init can fall back to storage when a provider download
# fails (GitHub's release downloads, releases.hashicorp.com's SHA256SUMS).
#
# Each provider is copied from the version sources.json gives on: every
# release since, for each platform it names. The modules' locks pin
# versions at or above it, and the nightly only moves them up; most of
# those locks are in private repositories this workflow can't read. Raise
# a provider's version when no lock pins anything older.
#
# An archive here is named by its SHA-256, the zh: hash a lock pins, and
# the registry's own shasum is checked against the download and storage's
# id against both, so Terraform checks what it gets: storage only has to be
# there. Copied archives are skipped by a HEAD request. Run by
# .github/workflows/mirror.yml; DRY_RUN=1 lists what it would copy.
set -euo pipefail

STORAGE="${STORAGE:-https://storage.sustenaut.eu}"
SOURCES="${SOURCES:-mirror/sources.json}"
REGISTRY=registry.terraform.io
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

token() {
  curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=storage.sustenaut.eu" | jq -r .value
}

there() { curl -fsI -o /dev/null "$STORAGE/terraform/f/$1/$2"; }

# Whether version $1 is $2 or later (releases only: no -prerelease).
since() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }

copied=0 skipped=0
platforms="$(jq -r '.terraform.platforms[]' "$SOURCES")"
while IFS=$'\t' read -r address from; do
  host="${address%%/*}" rest="${address#*/}"
  namespace="${rest%%/*}" type="${rest#*/}"
  if [ "$host" != "$REGISTRY" ]; then
    echo "::error::$address: only $REGISTRY providers are copied"
    exit 1
  fi
  api="https://$REGISTRY/v1/providers/$namespace/$type"
  for version in $(curl -fsS --retry 5 --retry-all-errors "$api/versions" | jq -r '.versions[].version' | sort -V); do
    since "$version" "$from" || continue
    for platform in $platforms; do
      download="$(curl -fsS --retry 5 --retry-all-errors "$api/$version/download/${platform%_*}/${platform#*_}")"
      name="$(jq -r .filename <<<"$download")"
      sha="$(jq -r .shasum <<<"$download")"
      url="$(jq -r .download_url <<<"$download")"
      if there "$sha" "$name"; then
        skipped=$((skipped + 1))
        continue
      fi
      if [ -n "${DRY_RUN:-}" ]; then
        echo "would copy $address $version $platform ($sha)"
        copied=$((copied + 1))
        continue
      fi
      curl -fsSL --retry 5 --retry-all-errors -o "$work/$name" "$url"
      actual="$(sha256sum "$work/$name" | cut -d' ' -f1)"
      [ "$actual" = "$sha" ] || { echo "::error::$name: the registry says $sha, the download is $actual"; exit 1; }
      id="$(curl -fsS --retry 3 --retry-all-errors -H "Authorization: Bearer $(token)" \
        -F "file=@$work/$name;filename=$name" -F "subject=$address" "$STORAGE/terraform/files" | jq -r .id)"
      [ "$id" = "$sha" ] || { echo "::error::$name: storage named it $id, not $sha"; exit 1; }
      echo "copied $address $version $platform ($sha)"
      copied=$((copied + 1))
      rm -f "$work/$name"
    done
  done
done < <(jq -r '.terraform.providers | to_entries[] | [.key, .value] | @tsv' "$SOURCES")

echo "$copied copied, $skipped already there"
