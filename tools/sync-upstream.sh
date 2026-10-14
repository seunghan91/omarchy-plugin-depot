#!/bin/bash
# Bring the Korean edition up to date with upstream Plugin Depot.
#
#   tools/sync-upstream.sh            merge upstream/main, re-apply identity, test
#   tools/sync-upstream.sh --catalog  also re-translate changed descriptions
#
# Stops at the first conflict or failing check and leaves the tree for a human.
# Nothing is pushed.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

git remote get-url upstream >/dev/null 2>&1 \
  || git remote add upstream https://github.com/OmarCodeHub/omarchy-marketplace.git
[[ -z $(git status --porcelain) ]] \
  || { echo "working tree has changes or untracked files; commit or set them aside first" >&2; exit 1; }

git fetch -q upstream
before=$(git rev-parse HEAD)
git merge --no-edit upstream/main || {
  echo "merge conflict: resolve, commit, then run tools/apply-fork-identity.sh" >&2
  exit 1
}

tools/apply-fork-identity.sh
node test-i18n.js --report | tail -3
if ! node test-i18n.js >/dev/null; then
  echo "new upstream strings need Korean in I18n.js (see above), then commit" >&2
  exit 1
fi
bash -n bin/*

if [[ ${1:-} == --catalog ]]; then
  python3 tools/translate-catalog.py --catalog https://plugins.omarchy.org/catalog.json
  python3 tools/check-catalog-ko.py
fi

# Only what this script changed: tracked files it rewrote, and the translation
# file it regenerates. Never anything else that happens to be lying around.
if [[ -n $(git status --porcelain --untracked-files=no) || -n $(git status --porcelain -- i18n/catalog.ko.json) ]]; then
  git add -u
  git add -- i18n/catalog.ko.json
  git commit -q -m "Re-apply the Korean edition after merging upstream"
fi
echo "synced: ${before:0:7} -> $(git rev-parse --short HEAD)"
