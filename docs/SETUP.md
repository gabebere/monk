# Developer setup

This guide creates a development build under identifiers owned by your Apple Developer account. The [engineering handbook](README.md) indexes product, architecture, troubleshooting, and release procedures.

## Requirements

- Mac with Xcode 26.4 or newer SDKs; CI pins its own specific Xcode version in `.github/workflows/apple-ci.yml`.
- Apple Developer account/team and appropriate signing profiles for real-device capabilities.
- iOS/iPadOS 18.5 or newer runtime for the universal app; macOS 14 or newer for MonkOS.
- Real phone/tablet/Mac for native enforcement and signed-distribution acceptance.

The minimum build SDK and runtime are different requirements. Optional installed-app data access requires iOS/iPadOS 26.4+, authorization, and regional eligibility; ordinary token-based app selection remains available on supported older runtimes and outside eligible regions. Simulator builds cannot certify Screen Time or distribution behavior.

## 1. Configure the checkout

```sh
git clone https://github.com/gabebere/monk.git
cd monk
cp Configurations/Local.xcconfig.example Configurations/Local.xcconfig
```

Edit the ignored `Configurations/Local.xcconfig`:

```xcconfig
MONK_DEVELOPMENT_TEAM = YOUR_TEAM_ID
MONK_BUNDLE_IDENTIFIER = com.example.Monk
MONK_MAC_BUNDLE_IDENTIFIER = com.example.Monk.mac
MONK_CLOUDKIT_CONTAINER = iCloud.com.example.Monk
MONK_APP_GROUP = group.com.example.Monk
```

The upstream defaults live in `Configurations/Monk.xcconfig`; version/build values live in `Configurations/Version.xcconfig`. A fork must provision the corresponding Apple resources; changing the text alone is insufficient. Do not change bundle/container/group identities of an installed product merely to reorganize source folders.

## 2. Create Apple resources

Create explicit App IDs for:

- `MONK_BUNDLE_IDENTIFIER` (the universal iPhone/iPad app).
- `MONK_BUNDLE_IDENTIFIER.HardBlockShieldUIExtension`.
- `MONK_BUNDLE_IDENTIFIER.DeviceActivityMonitor`.
- `MONK_MAC_BUNDLE_IDENTIFIER`.

Create `MONK_APP_GROUP` and associate the mobile app and both extensions. Create `MONK_CLOUDKIT_CONTAINER` and associate both app identifiers. Configure capabilities to match checked-in entitlements:

| Target | Required capability boundary |
| --- | --- |
| Mobile app | Family Controls, App Group, CloudKit, push; optional App and Website Usage data access |
| Shield extension | Family Controls and the same mobile App Group |
| Device Activity Monitor | Family Controls and the same mobile App Group |
| Mac app | CloudKit, Apple Events automation, hardened runtime; existing calendar permission for optional local recording |

Request Family Controls **distribution** authorization for the app and relevant extensions before TestFlight/App Store delivery. Development approval is not distribution approval. The optional App and Website Usage entitlement does not make its data API available to non-EU customers. Check actual final signed entitlements rather than assuming every profile matches a source file.

## 3. Open and sign

```sh
open Monk.xcodeproj
```

Inspect Signing & Capabilities on `Monk`, both mobile extensions, and `MonkMac`. Select/authenticate the correct team and refresh development profiles as needed. The mobile app and extensions must share App Group identity and version/build values. Both applications must use the same intended container and cloud environment for a sync test.

## 4. Validate and build

```sh
./script/ci.sh validate
./script/ci.sh mobile
./script/ci.sh mac
```

Equivalent direct Xcode commands:

```sh
xcodebuild -project Monk.xcodeproj -scheme Monk \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Monk.xcodeproj -scheme MonkMac \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild test -project Monk.xcodeproj -scheme MonkMac \
  -destination 'platform=macOS'
```

To build, install at a stable local path, and launch the developer's Mac build:

```sh
./script/build_and_run.sh
```

The launcher respects refusal to quit during active enforcement. Complete the expired session or use the ordinary product controls when allowed before relaunching; do not force termination to make development tooling succeed. This launcher produces a development installation, not the direct-distribution artifact.

## 5. Authorize each device

Grant Screen Time access on phone/tablet and select local apps/browsers. On Mac, grant required automation permissions and supported browser automation settings. Each device's opaque tokens and local paths remain local. Map unresolved remote app requests explicitly if optional app-name discovery is unavailable.

## 6. Initialize and verify CloudKit

Follow [CloudKit operations](runbooks/CLOUDKIT.md): use signed builds in the same environment, exercise each record family, verify catalog queries/subscriptions, and test account isolation. Before distribution, promote additive schema changes to Production and test actual release-signed phone/tablet/Mac artifacts there. Repository configuration does not prove that deployment occurred.

## Release and troubleshooting

Use [release engineering](RELEASES.md) to produce signed archives/exports and the Mac notarized package. Use [sync recovery](runbooks/SYNC_RECOVERY.md) for pending writes or unmatched apps. Build failures should be classified by source, toolchain/assets, signing, or execution permissions; [issue 006](issues/006-build-and-verification.md) records the audit environment limitations.

Windows setup remains separate in [Windows/README.md](../Windows/README.md).
