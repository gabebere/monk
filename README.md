# Monk

Monk is an allowlist-first focus app for Mac, iPhone, and iPad. Each session has only four inputs: what you are doing, how long it lasts, which apps are allowed, and which websites are allowed. Everything else is blocked until the timer ends.

Sessions sync through the user's private iCloud account. Each device applies the same commitment using the enforcement APIs available on that platform. Portable app names sync so each device can resolve its local counterpart; opaque Screen Time tokens never leave the device that created them.

## Targets

- `Monk`: the iPhone and iPad app.
- `MonkMac`: the macOS menu-bar app and `Option-Space` command panel.
- `HardBlockShieldUIExtension`: the iOS and iPadOS blocked-content screen.
- `MonkDeviceActivityMonitor`: ends mobile enforcement when the session expires.
- `MonkMacTests`: policy, duration, browser, and sync-model tests.

There are no accounts, analytics SDKs, subscriptions, reminders, calendar or health integrations, onboarding flows, or third-party package dependencies.

## Development

Open the project in Xcode:

```sh
open Monk.xcodeproj
```

Build the mobile app for Simulator:

```sh
xcodebuild -project Monk.xcodeproj -scheme Monk -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

Build and launch the Mac app:

```sh
./script/build_and_run.sh
```

Run the Mac policy tests:

```sh
xcodebuild test -project Monk.xcodeproj -scheme MonkMac -destination 'platform=macOS'
```

Mobile enforcement requires Apple's Family Controls capability. Cross-device sync requires the same iCloud account on each device and the `iCloud.com.gbr.Monk` CloudKit container.

## Distribution

The iPhone and iPad app is structured for App Store distribution. Before its first upload:

1. Request Apple’s Family Controls distribution capability for `com.gbr.Monk`, `com.gbr.Monk.HardBlockShieldUIExtension`, and `com.gbr.Monk.DeviceActivityMonitor`.
2. Deploy the `iCloud.com.gbr.Monk` CloudKit schema to the production environment.
3. Create the app record in App Store Connect, archive the `Monk` scheme, and validate the archive in Xcode Organizer.
4. Complete the App Privacy form consistently with `PrivacyInfo.xcprivacy`: Monk does not track users or send data to the developer; focus data is stored in the user’s private iCloud database.

The full Mac app is intended for direct distribution, not the Mac App Store. Its app and website enforcement requires controlling other applications and browser tabs, while the Mac App Store requires App Sandbox. Preserve the full implementation by signing the `MonkMac` archive with a Developer ID Application certificate and notarizing it before distribution.
