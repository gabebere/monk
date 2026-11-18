# Repository Guidelines

## Project Structure

- `Monk/`: iPhone and iPad SwiftUI app.
- `MonkMac/`: macOS SwiftUI menu-bar app.
- `HardBlockShieldExtension/`: Managed Settings shield appearance.
- `MonkDeviceActivityMonitor/`: Device Activity expiry extension.
- `Shared/`: source compiled by both app targets.
- `MonkMacTests/`: macOS policy and model tests.
- `script/`: local build and launch tooling.
- `Configurations/Version.xcconfig`: Apple product version and platform build numbers.
- `release/`: release readiness and evidence manifests; local products go in ignored `release/artifacts/`.
- `docs/README.md`: engineering handbook, platform contracts, data contract, and runbooks.
- `.github/`: CI, review ownership, issue templates, and declarative repository settings.

## Build and Test Commands

- Open Xcode: `open Monk.xcodeproj`
- List targets: `xcodebuild -list -project Monk.xcodeproj`
- Build mobile: `xcodebuild -project Monk.xcodeproj -scheme Monk -configuration Debug -destination 'generic/platform=iOS Simulator' build`
- Build Mac: `xcodebuild -project Monk.xcodeproj -scheme MonkMac -configuration Debug -destination 'platform=macOS' build`
- Test Mac: `xcodebuild test -project Monk.xcodeproj -scheme MonkMac -destination 'platform=macOS'`
- Build and launch Mac: `./script/build_and_run.sh`
- Validate repository contracts and infrastructure tests: `./script/ci.sh validate`
- Run policy/service XCTest suites without app startup or UI assets: `./script/test_core.sh` (does not replace full builds).
- Reproduce unsigned Apple CI: `./script/ci.sh mobile` and `./script/ci.sh mac`
- Create signed local candidates: see `docs/RELEASES.md`; archive/export is separate from publishing.

## Code Style

- Follow Swift API Design Guidelines with 4-space indentation and same-line braces.
- Use `UpperCamelCase` for types and `lowerCamelCase` for properties and functions.
- Keep one primary type per file and name the file after it.
- Prefer explicit imports and small SwiftUI views with clear state ownership.
- Add or update tests for policy, parsing, or enforcement behavior changes.
- Add shared source to both application targets explicitly; target membership is not inferred from the `Shared/` directory.
- Treat `docs/DATA_CONTRACT.md` as the cross-platform wire contract and document additive schema changes and migration.

## Product Boundaries

- Monk is intentionally allowlist-only and minimal.
- Do not add accounts, analytics, subscriptions, productivity integrations, or onboarding systems without an explicit product decision.
- An active session cannot be ended early.
- Cross-device state belongs in the user's private CloudKit database; local app selections stay private to each platform.
- iPhone and iPad ship one universal binary with separate device acceptance gates. Mac uses the same product version and its own build counter.
- A version in source does not mean a release has shipped. Update `release/1.0.0.json` only with actual verification evidence.

## Security

- Never commit secrets or credentials.
- Preserve the Family Controls, App Group, CloudKit, and Apple Events capabilities required by enforcement.
- Keep assets license-compliant and avoid storing sensitive data in `UserDefaults`.
