#!/usr/bin/env bash
# Copies the PyPI files the requirements locks pin into storage's pypi
# tenant, which serves them as a simple repository index (PEP 503) at
# /pypi/simple/<project>/, so an install can fall back to storage when PyPI
# fails: pip install --index-url https://storage.sustenaut.eu/pypi/simple/.
#
# The pins are each name==version and its sha256 hashes in the
# requirements*.lock files mirror/locks.sh fetched into $LOCKS. A lock pins
# every platform's wheel, so only those CI and our machines install are
# copied: pure wheels, and CPython 3.12 to 3.14 (or abi3) on manylinux
# x86_64, or the sdist of a pin with none of those. Wheels pinned by URL
# (our own releases) are mirror/wheels.sh's.
#
# A file here is named by its SHA-256, the hash a lock pins, and PyPI's own
# digest is checked against the download and storage's id against both, so
# pip checks what it gets: storage only has to be there. Copied files are
# skipped by a HEAD request. Run by .github/workflows/mirror.yml; DRY_RUN=1
# lists what it would copy.
set -euo pipefail

STORAGE="${STORAGE:-https://storage.sustenaut.eu}"
LOCKS="${LOCKS:?LOCKS is where mirror/locks.sh put the lock files}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

token() {
  curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=storage.sustenaut.eu" | jq -r .value
}

there() { curl -fsI -o /dev/null "$STORAGE/pypi/f/$1/$2"; }

# What to copy: "<project>\t<file>\t<sha256>\t<url>", from the locks and PyPI's JSON API.
plan() {
  python3 -I - "$LOCKS" <<'PY'
import json
import pathlib
import re
import sys
import time
import urllib.request

pins = {}
for lock in pathlib.Path(sys.argv[1]).rglob("requirements*.lock"):
    # A requirement and its hashes, joined across the backslashed lines.
    for entry in re.sub(r"\\\s*\n", " ", lock.read_text(encoding="utf-8")).splitlines():
        found = re.match(r"([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[^\]]*\])?==([^\s;]+)", entry)
        if found:
            key = (re.sub(r"[-_.]+", "-", found[1]).lower(), found[2])
            pins.setdefault(key, set()).update(re.findall(r"--hash=sha256:([0-9a-f]{64})", entry))

PYTHONS = {"cp312", "cp313", "cp314"}


def installs(name):
    """Whether a wheel installs on CI or our machines: pure, or CPython 3.12-3.14 (or abi3) on manylinux x86_64."""
    python, abi, platform = name[:-4].split("-")[-3:]
    if platform == "any":
        return any(tag.startswith("py3") for tag in python.split("."))
    linux = any("manylinux" in tag and tag.endswith("x86_64") for tag in platform.split("."))
    return linux and (bool(PYTHONS & set(python.split("."))) or "abi3" in abi)


def release(project, version):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(f"https://pypi.org/pypi/{project}/{version}/json", timeout=30) as answer:
                return json.load(answer)["urls"]
        except Exception as error:  # noqa: BLE001 - tried again, then reported
            if attempt == 4:
                print(f"::warning::{project} {version}: PyPI did not answer ({error})", file=sys.stderr)
                return []
            time.sleep(2 ** attempt)


for (project, version), hashes in sorted(pins.items()):
    files = [f for f in release(project, version) if f["digests"]["sha256"] in hashes]
    wheels = [f for f in files if f["filename"].endswith(".whl") and installs(f["filename"])]
    chosen = wheels or [f for f in files if f["packagetype"] == "sdist"][:1]
    for f in chosen:
        print(project, f["filename"], f["digests"]["sha256"], f["url"], sep="\t")
PY
}

copied=0 skipped=0
while IFS=$'\t' read -r project name sha url; do
  if there "$sha" "$name"; then
    skipped=$((skipped + 1))
    continue
  fi
  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "would copy $project $name ($sha)"
    copied=$((copied + 1))
    continue
  fi
  curl -fsSL --retry 5 --retry-all-errors -o "$work/$name" "$url"
  actual="$(sha256sum "$work/$name" | cut -d' ' -f1)"
  [[ "$actual" == "$sha" ]] || { echo "::error::$name: PyPI says $sha, the download is $actual"; exit 1; }
  id="$(curl -fsS --retry 3 --retry-all-errors -H "Authorization: Bearer $(token)" \
    -F "file=@$work/$name;filename=$name" -F "subject=$project" "$STORAGE/pypi/files" | jq -r .id)"
  [[ "$id" == "$sha" ]] || { echo "::error::$name: storage named it $id, not $sha"; exit 1; }
  echo "copied $project $name ($sha)"
  copied=$((copied + 1))
  rm -f "$work/$name"
done < <(plan)

echo "$copied copied, $skipped already there"
