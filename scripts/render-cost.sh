#!/usr/bin/env bash
# Measures how much CPU time the sound engine needs per output sample, for every
# sound, using `lowdrift-render --bench` in a release build.
#
#   scripts/render-cost.sh                      # this checkout
#   scripts/render-cost.sh --compare origin/main  # this checkout and another commit
#
# With --compare, the other commit is built from a temporary worktree with this
# checkout's render tool, so both are measured the same way on the same machine.
# Informational only: timing on shared machines is noisy, so it never fails.
set -uo pipefail
cd "$(dirname "$0")/.."

compare=""
if [[ "${1:-}" == "--compare" ]]; then
    compare="${2:?--compare needs a commit}"
fi

bench() {
    local dir="$1" label="$2"
    echo "== $label"
    if ! (cd "$dir/LowdriftKit" && swift build -c release --product lowdrift-render >/dev/null 2>&1); then
        echo "(could not build $label)"
        return 0
    fi
    (cd "$dir/LowdriftKit" && .build/release/lowdrift-render --bench --seconds 60)
}

bench "$PWD" "this checkout ($(git rev-parse --short HEAD))"

if [[ -n "$compare" ]]; then
    other=$(mktemp -d)
    if git worktree add --detach "$other/tree" "$compare" >/dev/null 2>&1; then
        cp LowdriftKit/Sources/LowdriftRender/main.swift "$other/tree/LowdriftKit/Sources/LowdriftRender/main.swift"
        bench "$other/tree" "$compare ($(git rev-parse --short "$compare"))"
        git worktree remove --force "$other/tree" >/dev/null 2>&1
    else
        echo "(could not check out $compare)"
    fi
    rm -rf "$other"
fi
exit 0
