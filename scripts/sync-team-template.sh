#!/bin/bash
# Copies the template repository's files, kept in docs/team/template/, into a checkout of
# github.com/noteling/team-tools-template, so the two stay identical. Change them here first, then:
#   scripts/sync-team-template.sh ../team-tools-template && cd ../team-tools-template && git diff
# Its LICENSE and .git are its own and left alone.
set -euo pipefail
TARGET="${1:?usage: scripts/sync-team-template.sh <path to a checkout of noteling/team-tools-template>}"
[ -e "$TARGET/.git" ] || { echo "$TARGET isn't a git checkout"; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
cd "$(dirname "$0")/.."
rsync -a --delete --exclude .git --exclude LICENSE --exclude __pycache__ --exclude .DS_Store docs/team/template/ "$TARGET"/
echo "Copied docs/team/template/ into $TARGET. Review with git diff there, then commit and push."
