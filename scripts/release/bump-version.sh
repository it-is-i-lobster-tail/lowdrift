#!/usr/bin/env bash
# Moves MARKETING_VERSION in Config/Version.xcconfig to the next release.
#   scripts/release/bump-version.sh minor     1.2.3 -> 1.3.0 (default: new features)
#   scripts/release/bump-version.sh patch     1.2.3 -> 1.2.4 (fixes only)
#   scripts/release/bump-version.sh major     1.2.3 -> 2.0.0 (redesign, one-way data change, dropped OS)
#   scripts/release/bump-version.sh 1.4.0     set an exact version
#   scripts/release/bump-version.sh --print   print the current version
# Prints the new version. Never touches CURRENT_PROJECT_VERSION.
set -euo pipefail
cd "$(dirname "$0")/../.."

xcconfig=Config/Version.xcconfig
current=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([0-9.]+)[[:space:]]*$/\1/p' "$xcconfig")
if ! [[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "bump-version: cannot read MARKETING_VERSION from $xcconfig" >&2
    exit 1
fi
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

case "${1:-}" in
    --print) echo "$current"; exit 0 ;;
    major) next="$((major + 1)).0.0" ;;
    minor) next="$major.$((minor + 1)).0" ;;
    patch) next="$major.$minor.$((patch + 1))" ;;
    *)
        if [[ "${1:-}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
            next=$1
        else
            echo "usage: $0 major|minor|patch|X.Y.Z|--print" >&2
            exit 2
        fi
        ;;
esac

if [ "$(printf '%s\n%s\n' "$current" "$next" | sort -V | tail -1)" != "$next" ] || [ "$current" = "$next" ]; then
    echo "bump-version: $next is not higher than $current" >&2
    exit 1
fi

sed -i.bak -E "s/^([[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*)[0-9.]+/\1$next/" "$xcconfig"
rm -f "$xcconfig.bak"
echo "$next"
