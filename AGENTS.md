# Repository Guidelines

## Project Structure

- `Monk/`: iPhone and iPad SwiftUI app.
- `MonkMac/`: macOS SwiftUI menu-bar app.
- `HardBlockShieldExtension/`: Managed Settings shield appearance.
- `MonkDeviceActivityMonitor/`: Device Activity expiry extension.
- `Shared/`: source compiled by both app targets.
- `MonkMacTests/`: macOS policy and model tests.
- `script/`: local build and launch tooling.

## Build and Test Commands

- Open Xcode: `open Monk.xcodeproj`
- List targets: `xcodebuild -list -project Monk.xcodeproj`
- Build mobile: `xcodebuild -project Monk.xcodeproj -scheme Monk -configuration Debug -destination 'generic/platform=iOS Simulator' build`
- Build Mac: `xcodebuild -project Monk.xcodeproj -scheme MonkMac -configuration Debug -destination 'platform=macOS' build`
- Test Mac: `xcodebuild test -project Monk.xcodeproj -scheme MonkMac -destination 'platform=macOS'`
- Build and launch Mac: `./script/build_and_run.sh`

## Code Style

- Follow Swift API Design Guidelines with 4-space indentation and same-line braces.
- Use `UpperCamelCase` for types and `lowerCamelCase` for properties and functions.
- Keep one primary type per file and name the file after it.
- Prefer explicit imports and small SwiftUI views with clear state ownership.
- Add or update tests for policy, parsing, or enforcement behavior changes.

## Product Boundaries

- Monk is intentionally allowlist-only and minimal.
- Do not add accounts, analytics, subscriptions, productivity integrations, or onboarding systems without an explicit product decision.
- An active session cannot be ended early.
- Cross-device state belongs in the user's private CloudKit database; local app selections stay private to each platform.

## Security

- Never commit secrets or credentials.
- Preserve the Family Controls, App Group, CloudKit, and Apple Events capabilities required by enforcement.
- Keep assets license-compliant and avoid storing sensitive data in `UserDefaults`.
