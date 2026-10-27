# Lowdrift privacy

Lowdrift collects nothing.

- **No data collection.** No analytics, crash reporting, advertising
  identifiers, accounts or sign-in.
- **No network.** The app contains no networking code and makes no network
  requests. It works the same in Airplane Mode.
- **No permissions.** No microphone, location, contacts, photos, Bluetooth
  scanning, local network or tracking prompts. Audio is played, never recorded.
- **No purchases.** Free, with no subscriptions or in-app purchases.
- **On-device settings only.** The last selected sound and each sound's three
  slider values are stored in the app's own `UserDefaults` on the iPhone. They
  are never transmitted and are removed when the app is deleted.

## App Store privacy disclosure

- Data Used to Track You: **None**
- Data Linked to You: **None**
- Data Not Linked to You: **None** (“Data Not Collected”)

The bundled privacy manifest (`Lowdrift/Resources/PrivacyInfo.xcprivacy`)
declares no tracking, no tracking domains and no collected data. It lists one
required-reason API: `UserDefaults` (reason `CA92.1`, the app's own
settings).

`scripts/privacy-audit.sh` checks this in CI. It fails if shipped code uses
networking, tracking, location, recording, purchase or logging APIs. It also
fails if `Info.plist` requests any permission, or if the project gains
entitlements or third-party packages.
