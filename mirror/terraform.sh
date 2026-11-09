#!/usr/bin/env bash
# Copies the Terraform providers the modules' locks pin into storage's
# terraform tenant, which serves them by Terraform's provider network mirror
# protocol, so an init can fall back to storage when a provider download
# fails (GitHub's release downloads, releases.hashicorp.com's SHA256SUMS).
#
# The pins are each provider and version in the .terraform.lock.hcl files
# mirror/locks.sh fetched into $LOCKS, copied for each platform
# mirror/sources.json lists (CI's linux_amd64).
#
# An archive here is named by its SHA-256, the zh: hash a lock pins, and
# the registry's own shasum is checked against the download and storage's
# id against both, so Terraform checks what it gets: storage only has to be
# there. Copied archives are skipped by a HEAD request. Run by
# .github/workflows/mirror.yml; DRY_RUN=1 lists what it would copy.
set -euo pipefail

STORAGE="${STORAGE:-https://storage.sustenaut.eu}"
SOURCES="${SOURCES:-mirror/sources.json}"
LOCKS="${LOCKS:?LOCKS is where mirror/locks.sh put the lock files}"
REGISTRY=registry.terraform.io
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

token() {
  curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=storage.sustenaut.eu" | jq -r .value
}

there() { curl -fsI -o /dev/null "$STORAGE/terraform/f/$1/$2"; }

# Each provider and version a lock pins, once: "<address>\t<version>".
pins() {
  find "$LOCKS" -name .terraform.lock.hcl -print0 | xargs -0 -r awk '
    /^provider "/ { split($0, q, "\""); address = q[2] }
    /^  version *= *"/ { split($0, q, "\""); if (address != "") print address "\t" q[2]; address = "" }
  ' | sort -u
}

copied=0 skipped=0
platforms="$(jq -r '.terraform.platforms[]' "$SOURCES")"
while IFS=$'\t' read -r address version; do
  host="${address%%/*}" rest="${address#*/}"
  namespace="${rest%%/*}" type="${rest#*/}"
  if [[ "$host" != "$REGISTRY" ]]; then
    echo "::warning::$address: only $REGISTRY providers are copied"
    continue
  fi
  api="https://$REGISTRY/v1/providers/$namespace/$type"
  for platform in $platforms; do
    download="$(curl -fsS --retry 5 --retry-all-errors "$api/$version/download/${platform%_*}/${platform#*_}")"
    name="$(jq -r .filename <<<"$download")"
    sha="$(jq -r .shasum <<<"$download")"
    url="$(jq -r .download_url <<<"$download")"
    if there "$sha" "$name"; then
      skipped=$((skipped + 1))
      continue
    fi
    if [[ -n "${DRY_RUN:-}" ]]; then
      echo "would copy $address $version $platform ($sha)"
      copied=$((copied + 1))
      continue
    fi
    curl -fsSL --retry 5 --retry-all-errors -o "$work/$name" "$url"
    actual="$(sha256sum "$work/$name" | cut -d' ' -f1)"
    [[ "$actual" == "$sha" ]] || { echo "::error::$name: the registry says $sha, the download is $actual"; exit 1; }
    id="$(curl -fsS --retry 3 --retry-all-errors -H "Authorization: Bearer $(token)" \
      -F "file=@$work/$name;filename=$name" -F "subject=$address" "$STORAGE/terraform/files" | jq -r .id)"
    [[ "$id" == "$sha" ]] || { echo "::error::$name: storage named it $id, not $sha"; exit 1; }
    echo "copied $address $version $platform ($sha)"
    copied=$((copied + 1))
    rm -f "$work/$name"
  done
done < <(pins)

echo "$copied copied, $skipped already there"
