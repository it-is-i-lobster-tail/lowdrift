#!/usr/bin/env bash
# Builds Lowdrift for the iOS Simulator and runs the simulator tests.
#   scripts/ci-ios.sh            app build + LowdriftUITests + LowdriftAudioTests (package)
#   scripts/ci-ios.sh --all      every LowdriftKit test target in the simulator (slow in Debug)
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

# The built app: background audio declared, App Intents metadata extracted (so
# Shortcuts and Siri see the intents), nothing network/tracking-related linked.
app=$(find "$derived/Build/Products" -maxdepth 2 -name Lowdrift.app -type d | head -1)
echo "UIBackgroundModes: $(plutil -extract UIBackgroundModes json -o - "$app/Info.plist")"
if [ ! -d "$app/Metadata.appintents" ]; then
    echo "App Intents metadata missing from the app bundle" >&2
    exit 1
fi
echo "App Intents metadata: $(ls "$app/Metadata.appintents" | tr '\n' ' ')"
# Debug builds keep the code in Lowdrift.debug.dylib; check whichever binaries
# exist. Only frameworks count: Swift overlays such as libswiftCoreLocation are
# weak-linked automatically through system modules' own imports.
forbidden='/(Network|StoreKit|AdSupport|AppTrackingTransparency|CoreLocation|WebKit)\.framework/'
for binary in "$app/Lowdrift" "$app/Lowdrift.debug.dylib"; do
    [ -f "$binary" ] || continue
    echo "Linked by $(basename "$binary"):"
    otool -L "$binary" | sed 1d
    if otool -L "$binary" | grep -E "$forbidden"; then
        echo "Unexpected framework linked" >&2
        exit 1
    fi
done

xcodebuild "${common[@]}" test-without-building -only-testing:LowdriftUITests -resultBundlePath build/UITests.xcresult

# LowdriftKit's tests in the simulator: the real AVAudioSourceNode render block
# inside AVAudioEngine on iOS (the DSP and Core tests also run with `swift test`).
package_scheme=$(cd LowdriftKit && xcodebuild -list -json 2>/dev/null | python3 -c '
import json, sys
text = sys.stdin.read()
data = json.loads(text[text.index("{"):])
schemes = [s for v in data.values() if isinstance(v, dict) for s in v.get("schemes", [])]
print("LowdriftKit-Package" if "LowdriftKit-Package" in schemes else "LowdriftKit")
print(f"Package schemes: {schemes}", file=sys.stderr)
')
only=(-only-testing:LowdriftAudioTests)
if [ "${1:-}" = "--all" ]; then
    only=()
fi
(cd LowdriftKit && xcodebuild -scheme "$package_scheme" -destination "id=$udid" \
    -derivedDataPath ../build/PackageDerivedData test ${only[@]+"${only[@]}"} \
    -resultBundlePath ../build/PackageTests.xcresult)
