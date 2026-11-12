#!/usr/bin/env bash
# Push, then prove it. A quiet `git push` can exit 0 while nothing moves — that happened four
# times in this repo before anyone noticed. Never report a push as done without this assertion.
#
#   bash scripts/push.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

branch=$(git rev-parse --abbrev-ref HEAD)
echo "pushing $branch"
git push origin "$branch" || { echo "FAIL: git push returned non-zero"; exit 1; }

git fetch -q origin "$branch" || { echo "FAIL: could not fetch origin/$branch"; exit 1; }
ahead=$(git rev-list --count "origin/$branch..HEAD")
behind=$(git rev-list --count "HEAD..origin/$branch")

if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
  echo "OK: origin/$branch matches HEAD ($(git rev-parse --short HEAD))"
  exit 0
fi

echo "FAIL: not in sync — $ahead ahead, $behind behind after pushing"
git log --oneline "origin/$branch..HEAD" | head -10
exit 1
