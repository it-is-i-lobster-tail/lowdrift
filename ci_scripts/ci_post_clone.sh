#!/bin/sh
# Xcode Cloud runs this right after cloning, before it builds.
#
# On the Alpha workflow (pushes to main) it writes TestFlight/WhatToTest.en-US.txt,
# which Xcode Cloud attaches to the build as TestFlight's "What to Test" notes,
# so internal testers see what changed. It never fails the build: if anything
# here goes wrong, the build simply has no notes.
#
# Every push to main is built, so "what changed since the last build" is the
# push's own commits: for a merged pull request, the commits on its branch;
# otherwise the pushed commit itself.
set -u

repo=${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$repo" || exit 0

# Pull requests and other workflows don't upload to TestFlight.
if [ -n "${CI_PULL_REQUEST_NUMBER:-}" ]; then
    echo "ci_post_clone: pull request build, no tester notes"
    exit 0
fi

# Xcode Cloud may clone shallowly; the notes need the merge's parents.
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    git fetch --quiet --deepen=200 origin 2>/dev/null || true
fi

version=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([0-9.]+).*/\1/p' Config/Version.xcconfig)
commit=${CI_COMMIT:-$(git rev-parse HEAD)}
short=$(printf %s "$commit" | cut -c1-7)

if git rev-parse --verify -q "$commit^2" >/dev/null; then
    title=$(git log -1 --format=%b "$commit" | sed -n '/./{p;q;}')
    [ -n "$title" ] || title=$(git log -1 --format=%s "$commit")
    changes=$(git log --no-merges --format='- %s' "$commit^1..$commit^2" 2>/dev/null | head -40)
else
    title=$(git log -1 --format=%s "$commit")
    changes=""
fi

notes_dir=TestFlight
mkdir -p "$notes_dir"
{
    echo "Lowdrift $version (${CI_BUILD_NUMBER:-?}), alpha build of main at $short"
    echo
    echo "$title"
    if [ -n "$changes" ]; then
        echo
        echo "$changes"
    fi
} | cut -c1-200 | head -c 3900 > "$notes_dir/WhatToTest.en-US.txt"

echo "ci_post_clone: wrote $notes_dir/WhatToTest.en-US.txt"
cat "$notes_dir/WhatToTest.en-US.txt"
exit 0
