# Set up a fork

This guide creates a development build under identifiers owned by your Apple Developer account. Changing the strings in the repository is not enough: the App Group, iCloud container, capabilities, and provisioning profiles must also exist in Apple's developer portal.

## Requirements

- a Mac with a recent Xcode release (Xcode 26.4 or newer is recommended);
- an Apple Developer account and team;
- iOS/iPadOS 18.5 or newer for the mobile app;
- macOS 14 or newer for MonkOS.

The basic UI can build for Simulator. Screen Time enforcement, CloudKit sync, app discovery, Siri integration, and desktop automation should be verified on real devices.

## 1. Clone and configure

```sh
git clone https://github.com/gabebere/monk.git
cd monk
cp Configurations/Local.xcconfig.example Configurations/Local.xcconfig
```

Edit `Configurations/Local.xcconfig`:

```xcconfig
MONK_DEVELOPMENT_TEAM = YOUR_TEAM_ID
MONK_BUNDLE_IDENTIFIER = com.example.Monk
MONK_MAC_BUNDLE_IDENTIFIER = com.example.Monk.mac
MONK_CLOUDKIT_CONTAINER = iCloud.com.example.Monk
MONK_APP_GROUP = group.com.example.Monk
```

`Local.xcconfig` is ignored by Git. The upstream defaults remain in `Configurations/Monk.xcconfig` and should not need editing in a fork.

## 2. Create Apple resources

In Certificates, Identifiers & Profiles, create explicit App IDs for:

- `MONK_BUNDLE_IDENTIFIER`;
- `MONK_BUNDLE_IDENTIFIER.HardBlockShieldUIExtension`;
- `MONK_BUNDLE_IDENTIFIER.DeviceActivityMonitor`;
- `MONK_MAC_BUNDLE_IDENTIFIER`.

Create the App Group named by `MONK_APP_GROUP` and associate it with the mobile app and both mobile extensions. Create the iCloud container named by `MONK_CLOUDKIT_CONTAINER` and associate it with the mobile and Mac App IDs.

Enable the capabilities already represented in the checked-in entitlements:

- Family Controls and App & Website Activity for the mobile app and extensions;
- iCloud / CloudKit for the mobile and Mac apps;
- Push Notifications for the mobile app's CloudKit subscription;
- App Groups for the mobile app and extensions;
- Apple Events automation for the Mac app.

Apple requires a separate request before Family Controls can be used in an App Store distribution profile. Development authorization does not automatically grant distribution authorization.

## 3. Open and sign

```sh
open Monk.xcodeproj
```

Select the `Monk` scheme, inspect each mobile target under **Signing & Capabilities**, and let Xcode create or refresh development profiles. Repeat for the `MonkMac` scheme. The team value normally comes from `Local.xcconfig`; Xcode may still ask you to authenticate your developer account.

## 4. Build

```sh
# Mobile Simulator build
xcodebuild -project Monk.xcodeproj -scheme Monk \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build

# Mac build
xcodebuild -project Monk.xcodeproj -scheme MonkMac \
  -configuration Debug -destination 'platform=macOS' build

# Mac tests
xcodebuild test -project Monk.xcodeproj -scheme MonkMac \
  -destination 'platform=macOS'
```

To build and launch the local Mac app in one step:

```sh
./script/build_and_run.sh
```

On first launch, grant the permissions Monk explains. macOS website enforcement also depends on the supported browser allowing automation.

## 5. Initialize CloudKit

Run signed development builds on two devices using the same Apple Account and create a focus. Confirm the current focus and application-catalog records appear in the CloudKit development environment.

Before distributing a release:

1. inspect the development schema in CloudKit Console;
2. deploy the schema to Production;
3. test a release-signed build against Production with a separate test Apple Account;
4. verify that focus records appear only in the user's private database.

## App Store and direct distribution

The iPhone/iPad target is intended for the App Store after the Family Controls distribution capability is approved for all relevant bundle IDs.

The full Mac target is intended for direct distribution. Archive it with a Developer ID Application certificate, notarize it, and staple the notarization ticket. Sandboxing the target for the Mac App Store would remove capabilities that the current enforcement design relies on.

## Windows

Windows has a separate build documented in `Windows/README.md`. It requires Windows 10/11 and the .NET 8 SDK; Inno Setup 6 is optional for producing an installer.
