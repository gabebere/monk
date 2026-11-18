# Monk for iPhone 1.0

Status: unreleased candidate. Target/scheme: `Monk`. App bundle: `$(MONK_BUNDLE_IDENTIFIER)` (upstream `com.gbr.Monk`). Minimum runtime: iOS 18.5. Distribution: the universal iPhone/iPad TestFlight/App Store application.

## Responsibility

The phone owns its SwiftUI focus composer, local Screen Time permission, opaque app/browser selections, local mappings, temporary app grants, and Managed Settings policy. `CrossDeviceFocusService` coordinates these with portable private CloudKit state. Shield appearance comes from `HardBlockShieldUIExtension`; Device Activity callbacks come from `MonkDeviceActivityMonitor`.

The app and both extensions share `$(MONK_APP_GROUP)`. Only the app needs the CloudKit container and push handling. Family Controls distribution authorization must be verified for each relevant bundle ID. The app's optional App and Website Usage data-access capability must not be confused with ordinary token-based Screen Time authorization.

## Interaction contract

A focus starts from an explicit local app/browser selection and portable remote requests. Local picker functionality is available with ordinary approved Screen Time access. Installed-app search is an optional enhancement when Apple's API actually provides data. Missing remote equivalents remain visible and can be mapped to a locally picked app without uploading the token. The UI does not promise worldwide automatic mobile app-name matching.

An active focus cannot be finished early. At zero, enforcement remains until the person extends or finishes. Temporary app access follows its explicit grant policy and does not end the commitment. Local enforcement must not depend on network availability.

## Release acceptance

- [ ] Clean and upgrade TestFlight installs on a supported phone.
- [ ] Ordinary Screen Time permission grant, denial, revocation, and recovery.
- [ ] Token picker on a non-EU distributed installation; eligible catalog access tested separately.
- [ ] Start, extend, finish, default blocking, browser allowlist, and temporary grant expiry.
- [ ] Local selection preserved after a remote defaults update with zero/partial matches.
- [ ] Manual remote-app mapping persists through relaunch and does not allow unrelated apps.
- [ ] Background/foreground reconciliation and offline retry with Mac and iPad.
- [ ] Account switch does not upload the previous account's pending focus.
- [ ] Actual embedded extensions, entitlements, version, and build inspected.

Record the device, OS, commit, mobile build, CloudKit environment, and result in the release evidence. The shared binary still requires separate iPad acceptance.
