#!/usr/bin/env bash
# Version check, run on every pull request (Linux, no Xcode needed).
#
# Fails if:
#   - Config/Version.xcconfig's MARKETING_VERSION is not MAJOR.MINOR.PATCH
#     (three integers, digits and dots only, at most 18 characters), or its
#     CURRENT_PROJECT_VERSION is not a plain integer;
#   - any target or configuration in the Xcode project sets MARKETING_VERSION
#     or CURRENT_PROJECT_VERSION itself (they would drift from the app's);
#   - the project's configurations do not use Version.xcconfig as their base;
#   - an Info.plist hard-codes CFBundleShortVersionString or CFBundleVersion.
#
# Prints the version on success, e.g. "version-check: 1.0.0".
set -euo pipefail
cd "$(dirname "$0")/../.."

xcconfig=Config/Version.xcconfig
status=0
fail() { echo "version-check: $*" >&2; status=1; }

setting() { # $1 = name; prints the value from the xcconfig
    sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]/]*)[[:space:]]*(\/\/.*)?$/\1/p" "$xcconfig"
}

[ -f "$xcconfig" ] || { echo "version-check: $xcconfig is missing" >&2; exit 1; }

version=$(setting MARKETING_VERSION)
build=$(setting CURRENT_PROJECT_VERSION)
[ "$(grep -cE '^[[:space:]]*MARKETING_VERSION[[:space:]]*=' "$xcconfig")" -eq 1 ] ||
    fail "$xcconfig must set MARKETING_VERSION exactly once"
[ "$(grep -cE '^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=' "$xcconfig")" -eq 1 ] ||
    fail "$xcconfig must set CURRENT_PROJECT_VERSION exactly once"

if ! [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    fail "MARKETING_VERSION '$version' is not MAJOR.MINOR.PATCH (digits and dots only)"
elif [ "${#version}" -gt 18 ]; then
    fail "MARKETING_VERSION '$version' is longer than Apple's 18 characters"
fi
if ! [[ "$build" =~ ^[1-9][0-9]*$ ]]; then
    fail "CURRENT_PROJECT_VERSION '$build' is not a positive integer"
elif [ "$build" != 1 ]; then
    fail "CURRENT_PROJECT_VERSION must stay 1 in the repo; Xcode Cloud stamps the real build number"
fi

for project in $(git ls-files '*.pbxproj'); do
    if grep -nE '(MARKETING_VERSION|CURRENT_PROJECT_VERSION)[[:space:]]*=' "$project"; then
        fail "$project sets a version in a target or configuration; set it only in $xcconfig"
    fi
    based=$(grep -cE 'baseConfigurationReference = [0-9A-F]+ /\* Version\.xcconfig \*/;' "$project" || true)
    if [ "$based" -lt 2 ]; then
        fail "$project: the project's Debug and Release configurations must use Version.xcconfig as their base"
    fi
done

for plist in $(git ls-files '*Info.plist'); do
    if grep -nE '<key>(CFBundleShortVersionString|CFBundleVersion)</key>' "$plist"; then
        fail "$plist hard-codes a version; Xcode generates it from $xcconfig"
    fi
done

if [ "$status" -eq 0 ]; then echo "version-check: $version"; fi
exit "$status"
