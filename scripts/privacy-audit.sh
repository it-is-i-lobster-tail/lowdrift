#!/usr/bin/env bash
# Checks the source tree for anything that could collect data, reach the network,
# record audio, track the user or sell something. Runs on macOS and Linux.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
fail() { echo "privacy-audit: $*" >&2; status=1; }

# Everything that ships in the app (the render tool and analysis helpers are developer-only).
shipped="Lowdrift LowdriftKit/Sources/LDAtomics LowdriftKit/Sources/LowdriftDSP LowdriftKit/Sources/LowdriftCore LowdriftKit/Sources/LowdriftAudio"
sources=$(find $shipped -name '*.swift' -o -name '*.c' -o -name '*.h')

# APIs and frameworks Lowdrift must never use.
forbidden='URLSession|URLRequest|NSURLConnection|import Network|NWConnection|NWPathMonitor|CFNetwork|WKWebView|SFSafariViewController|import StoreKit|SKPayment|import AdSupport|ASIdentifierManager|AppTrackingTransparency|ATTrackingManager|import CoreLocation|CLLocationManager|AVAudioRecorder|AVCaptureDevice|requestRecordPermission|inputNode|import CloudKit|NSUbiquitousKeyValueStore|import HealthKit|import Contacts|import Photos|UIPasteboard|os_log|Logger\(|print\('
if grep -nE "$forbidden" $sources; then
    fail "forbidden API found above"
fi

# No web addresses in shipped code.
if grep -nE 'https?://' $sources; then
    fail "URL found in shipped source above"
fi

# Info.plist: background audio only; no permission prompts or network exceptions.
plist=Config/Info.plist
grep -q '<string>audio</string>' "$plist" || fail "UIBackgroundModes audio missing"
if grep -nE 'UsageDescription|NSAppTransportSecurity|NSAllowsArbitraryLoads|NSBonjourServices|NSLocalNetwork' "$plist"; then
    fail "permission or network key found in $plist"
fi

# Privacy manifest: no tracking and no collected data.
manifest=Lowdrift/Resources/PrivacyInfo.xcprivacy
grep -A1 'NSPrivacyTracking</key>' "$manifest" | grep -q '<false/>' || fail "NSPrivacyTracking must be false"
grep -A1 'NSPrivacyCollectedDataTypes</key>' "$manifest" | grep -q '<array/>' || fail "NSPrivacyCollectedDataTypes must be empty"

# No entitlements beyond the defaults (background audio needs none).
if find . -name '*.entitlements' -not -path './.build/*' -not -path './LowdriftKit/.build/*' | grep -q .; then
    fail "unexpected entitlements file"
fi

# No third-party packages.
if grep -q '\.package(' LowdriftKit/Package.swift; then
    fail "LowdriftKit must not depend on external packages"
fi
if grep -q 'XCRemoteSwiftPackageReference' Lowdrift.xcodeproj/project.pbxproj; then
    fail "the Xcode project must not reference remote packages"
fi

[ "$status" -eq 0 ] && echo "privacy-audit: OK (no network, tracking, recording, purchases or logging APIs; no permissions requested)"
exit "$status"
