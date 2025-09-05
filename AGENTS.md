# Repository Guidelines

## Project Structure & Module Organization
- `Monk/`: App source (SwiftUI). Entry point `MonkApp.swift`; main UI in `ContentView.swift`; assets in `Assets.xcassets`.
- `MonkTests/`: Unit tests (XCTest).
- `MonkUITests/`: UI tests (XCUITest), including launch tests.
- `Monk.xcodeproj/`: Xcode project; open with `open Monk.xcodeproj`.

## Build, Test, and Development Commands
- Build (Debug, simulator): `xcodebuild -project Monk.xcodeproj -scheme Monk -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15' build`
- Run tests: `xcodebuild test -project Monk.xcodeproj -scheme Monk -destination 'platform=iOS Simulator,name=iPhone 15'`
- Open in Xcode: `open Monk.xcodeproj` (recommended for running and debugging).
- List schemes/targets: `xcodebuild -list -project Monk.xcodeproj`

## Coding Style & Naming Conventions
- Style: Follow Swift API Design Guidelines; 4‑space indentation; brace-on-same-line.
- Naming: `UpperCamelCase` for types (`MonkApp`), `lowerCamelCase` for vars/functions, `SCREAMING_SNAKE_CASE` for constants.
- Files: One primary type per file; name files after the main type or view (e.g., `ContentView.swift`).
- Imports: Prefer explicit imports; keep SwiftUI views small and composable.
- Lint/format: No repo-specific tools configured; use Xcode’s default formatting or SwiftFormat locally if desired.

## Testing Guidelines
- Frameworks: XCTest for unit tests, XCUITest for UI flows.
- Location: Place unit tests in `MonkTests/` and UI tests in `MonkUITests/` mirroring source structure.
- Naming: Methods start with `test…` and describe behavior, e.g., `testContentView_rendersGreeting()`.
- Scope: Add/adjust tests for every bug fix or new feature; cover view models and critical view logic.

## Commit & Pull Request Guidelines
- Commits: Imperative present tense (“Add…”, “Fix…”), small and focused. Optionally use Conventional Commits (e.g., `feat:`, `fix:`) for clarity.
- PRs: Include a concise description, screenshots for UI changes, and linked issues (e.g., `Closes #123`). Request review before merging.
- Checks: Ensure project builds and tests pass locally via `xcodebuild test`.

## Security & Configuration Tips
- Do not commit secrets or credentials; prefer env/config files excluded by `.gitignore`.
- Keep assets license-compliant; place app media under `Monk/Assets.xcassets`.
- Avoid storing sensitive data in `UserDefaults`; prefer Keychain when needed.

