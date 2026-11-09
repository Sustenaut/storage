#!/usr/bin/env bash
# Makes the sustenaut-storage-mirror GitHub App (apps/sustenaut-storage-mirror.json),
# which lets the mirror workflow read the lock files of Sustenaut's private
# repositories, and gives this repository its id and key. Run it once, from
# this repository's root on an up-to-date main, signed in to gh as an owner
# of Sustenaut, with a Bitwarden access token that can write the Sustenaut
# project at hand, and ./with-secrets' read token (BWS_ACCESS_TOKEN, or the
# line in .env) for step 2:
#
#   scripts/go-live-mirror-app.sh
#
# Each step says what it does and asks first; a step already done is
# skipped, and the first error stops it. It prints no secret.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root"
repo=Sustenaut/storage
manifest=apps/sustenaut-storage-mirror.json

step() { printf '\n== %s\n' "$*"; }
skip() { echo "   already done: $*"; }
ask() {
  local answer
  read -r -p "   $1 [y/N] " answer </dev/tty
  [[ $answer =~ ^[Yy] ]] || { echo "Stopped; run scripts/go-live-mirror-app.sh again to go on."; exit 1; }
}
has_variable() { gh variable list -R "$repo" --json name --jq '.[].name' | grep -qx "$1"; }

step "1. The app, its key in Bitwarden (./pubsec github-app create)"
# Made once: GitHub lists the app's installation on the owner (github-app
# create refuses to make it again anyway, once its values are in Bitwarden).
if gh api orgs/Sustenaut/installations --jq '.installations[].app_slug' | grep -qx sustenaut-storage-mirror; then
  skip "the app is installed on Sustenaut"
else
  ./pubsec github-app create --dry-run "$manifest"
  echo "   It opens GitHub in your browser to make the app, then its install page."
  echo "   Install it on all of Sustenaut's repositories: it can only read their contents."
  ask "Make the app?"
  ./pubsec github-app create "$manifest"
fi

step "2. Its id, installation id and key on $repo (./pubsec app-secrets)"
if has_variable MIRROR_APP_ID && has_variable MIRROR_APP_INSTALLATION_ID \
  && gh secret list -R "$repo" --json name --jq '.[].name' | grep -qx MIRROR_APP_KEY; then
  skip "MIRROR_APP_ID, MIRROR_APP_INSTALLATION_ID and MIRROR_APP_KEY are set"
else
  ./with-secrets ./pubsec app-secrets --check
  ask "Send them to $repo?"
  ./with-secrets ./pubsec app-secrets
fi

step "3. A mirror run that reads every lock the app reaches"
ask "Run the mirror workflow now?"
gh workflow run mirror.yml -R "$repo" --ref main
echo "   Started: gh run list -R $repo --workflow mirror.yml --limit 1"
echo "   Its locks job says how many lock files and repositories it read."
