#!/usr/bin/env bash
# Builds Lowdrift for the iOS Simulator and runs the simulator test targets.
#   scripts/ci-ios.sh            build + LowdriftAudioTests + LowdriftUITests
#   scripts/ci-ios.sh --all      also the DSP and Core package tests (slow in Debug)
set -euo pipefail
cd "$(dirname "$0")/.."

# Newest iOS runtime, preferring a standard "iPhone NN" model.
udid=$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        standard = re.fullmatch(r"iPhone \d+", name) is not None
        key = (version, standard, name)
        if best is None or key > best[0]:
            best = (key, device["udid"], name, runtime)
if best is None:
    sys.exit("No iPhone simulator available")
print(best[1])
print(f"Using {best[2]} ({best[3]})", file=sys.stderr)
')

mkdir -p build
derived=build/DerivedData
common=(-project Lowdrift.xcodeproj -scheme Lowdrift -destination "id=$udid" -derivedDataPath "$derived")

set +e
xcodebuild "${common[@]}" build-for-testing > build/xcodebuild-build.log 2>&1
code=$?
set -e
grep -E "error:|warning:" build/xcodebuild-build.log | sort -u | head -200 || true
tail -n 5 build/xcodebuild-build.log
[ "$code" -eq 0 ] || exit "$code"

# The built app: background audio declared, nothing network/tracking-related linked.
app=$(find "$derived/Build/Products" -maxdepth 2 -name Lowdrift.app -type d | head -1)
plutil -extract UIBackgroundModes json -o - "$app/Info.plist"
if otool -L "$app/Lowdrift" | grep -E "Network.framework|StoreKit|AdSupport|AppTrackingTransparency|CoreLocation|WebKit"; then
    echo "Unexpected framework linked" >&2
    exit 1
fi
echo "Linked frameworks:"
otool -L "$app/Lowdrift" | sed 1d

only=(-only-testing:LowdriftAudioTests -only-testing:LowdriftUITests)
if [ "${1:-}" = "--all" ]; then
    only=()
fi
xcodebuild "${common[@]}" test-without-building ${only[@]+"${only[@]}"} -resultBundlePath build/Tests.xcresult
