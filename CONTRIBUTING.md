# Contributing

Thank you for helping make Monk calmer, smaller, and more reliable.

## Product boundaries

Monk is an allowlist-first focus tool. Changes should preserve these constraints:

- an active focus cannot be ended early;
- users explicitly choose the apps and websites a task needs;
- cross-device state uses the user's private CloudKit database;
- opaque local app-selection tokens stay on their original platform;
- accounts, analytics, advertising, subscriptions, and broad productivity integrations are out of scope unless the product direction changes explicitly.

## Before opening a pull request

1. Create a branch from the current default branch.
2. Keep platform-specific enforcement inside its platform directory.
3. Add or update tests for parsing, policy, persistence, or enforcement behavior.
4. Build every target your change touches.
5. Describe the user-visible behavior and any new capability or entitlement requirements.

Apple verification commands:

```sh
xcodebuild -project Monk.xcodeproj -scheme Monk \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Monk.xcodeproj -scheme MonkMac \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild test -project Monk.xcodeproj -scheme MonkMac \
  -destination 'platform=macOS'
```

Windows verification runs from PowerShell:

```powershell
./Windows/scripts/build.ps1
```

## Style

Follow Swift API Design Guidelines, use four-space indentation, and keep one primary type per file. Prefer small SwiftUI views with clear state ownership and system frameworks over new dependencies.

Do not commit `Configurations/Local.xcconfig`, signing material, CloudKit exports containing user data, build output, or credentials.
