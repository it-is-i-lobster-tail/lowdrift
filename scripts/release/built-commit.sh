#!/usr/bin/env bash
# Finds the main commit whose build a staging or prod push should promote.
#   scripts/release/built-commit.sh [commit] [main-ref]
#     commit    the pushed staging/prod commit (default HEAD)
#     main-ref  main's head (default origin/main)
# Prints the main commit's full SHA.
#
# Staging and prod only ever receive merges: main -> staging, staging -> prod
# (merge commits, never squash or rebase). So from the pushed commit, follow
# each merge's second parent (the side that was merged in) until reaching a
# commit that is on main. A fast-forward lands directly on a main commit.
#
# Fails, instead of shipping an untested change, if:
#   - the walk reaches a non-merge commit that main never had (someone
#     committed straight to staging or prod), or
#   - the pushed commit's tree differs from the main commit's tree (something
#     landed on staging or prod that main never built).
# Needs full history (actions/checkout with fetch-depth: 0).
set -euo pipefail

commit=$(git rev-parse --verify "${1:-HEAD}^{commit}")
main=$(git rev-parse --verify "${2:-origin/main}^{commit}")

fail() { echo "built-commit: $*" >&2; exit 1; }

candidate=$commit
for _ in $(seq 1 50); do
    if git merge-base --is-ancestor "$candidate" "$main"; then
        break
    fi
    if second=$(git rev-parse --verify -q "$candidate^2"); then
        candidate=$second
    else
        fail "$(git log -1 --format='%h "%s"' "$candidate") is not on main and is not a merge. Changes reach staging and prod only by merging main (then staging) with a merge commit."
    fi
done
git merge-base --is-ancestor "$candidate" "$main" ||
    fail "no main commit found within 50 merges of $commit"

if [ "$(git rev-parse "$commit^{tree}")" != "$(git rev-parse "$candidate^{tree}")" ]; then
    echo "built-commit: $(git rev-parse --short "$commit") differs from the main commit it merged, $(git rev-parse --short "$candidate"):" >&2
    git diff --stat "$candidate" "$commit" >&2
    fail "promote only what main built: merge main into staging (and staging into prod) without other changes."
fi

echo "$candidate"
