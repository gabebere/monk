# Monk – macOS Port Plan (Option A: Native macOS target + MonkShared package)

This document is the handoff for adding a native macOS build of Monk. It assumes the current codebase:
- SwiftUI app targeting iOS + iPadOS in a single target.
- SwiftData models in `Monk/Models`, services in `Monk/Services`, utilities in `Monk/Utilities`, views in `Monk/Views`.
- iOS-only features: Screen Time (FamilyControls/ManagedSettings/DeviceActivity), Live Activities (ActivityKit), GoogleSignIn UI wrappers, RevenueCat paywall UI.
- UIKit-bound views/utilities exist (Haptics, AuthGatewayView, PaywallManager, FeedbackWebView, AnalyticsService).

This plan is compatible with Option A (separate macOS target + shared local Swift package) and adds repo-specific notes below.

## Goal
- Add a native macOS SwiftUI target (`MonkMac`) while keeping iPhone/iPad UX unchanged.
- Share platform-agnostic code via a local Swift Package (`MonkShared`).
- Keep platform-only code cleanly separated with conditional compilation.

## Recommended Architecture
1) **Create a native macOS target**
   - Xcode → File → New → Target… → macOS tab → App (SwiftUI).
   - Name: `MonkMac`. Bundle ID unique per target (e.g., `com.gbr.Monk.mac`).
   - Use SwiftUI lifecycle (@main).

2) **Create a local Swift package for shared code**
   - Xcode → File → New → Package… → Name `MonkShared`.
   - Add folders in the package:
     - `Models/` – SwiftData models (FocusSession, Project, Preferences).
     - `Services/` – FocusManager (with conditional ActivityKit), InsightsAnalyzer, RevenueCatService, EntitlementSyncService, AuthManager logic (no UI), Analytics, DateUtils, notification scheduler (UNUserNotificationCenter-only parts).
     - `UIShared/` – Pure SwiftUI components without iOS-only APIs (ProjectCard, generic cards, Theme, AnimatingBackground if no iOS-only imports).
   - Add the package to both targets (iOS + macOS) under Frameworks/Libraries.
   - Fix imports to `import MonkShared` where needed.
   - Repo note: there is already a `Monk/Shared/FocusSessionLiveActivity.swift` file that is ActivityKit-only and not a module. Move it into the iOS target (or rename that folder) to avoid confusing it with the new `MonkShared` package.

3) **Keep platform-only code out of Shared**
   - iOS-only (stay in iOS target):
     - Screen Time stack: FamilyControls, ManagedSettings, DeviceActivity, HardBlockManager, HardBlockStateStore.
     - Live Activities (ActivityKit), including `Monk/Shared/FocusSessionLiveActivity.swift` and `MonkLiveActivities/`.
     - GoogleSignIn UI wrappers.
     - RevenueCat paywall UI wrapper (RevenueCatUI, iOS-only modifiers).
     - UIKit-bound views/utilities: `Monk/Utilities/Haptics.swift`, `Monk/Views/AuthGatewayView.swift`, `Monk/Views/FeedbackWebView.swift`, `Monk/Services/PaywallManager.swift`, `Monk/Utilities/AnalyticsService.swift` (uses `UIDevice`).
     - iOS extension targets: `HardBlockShieldExtension/`, `DeviceActivity/`, `MonkLiveActivities/`.
   - macOS-only:
     - macOS @main App, Scenes, menus/commands, window management.
     - macOS notification permission handling (UNUserNotificationCenter still shared).
     - Optional macOS-specific layout (sidebar/toolbar, resizable windows).
   - Screen Time frameworks: decide per platform explicitly. If mac support is desired, keep policy/rule logic in `MonkShared` and import the Screen Time frameworks in the mac target where allowed.

4) **Conditional compilation guards**
   - Wrap iOS-only imports/uses:
     - `#if os(iOS)` or `#if canImport(ActivityKit)` for Live Activities.
     - `#if canImport(FamilyControls)` / `#if canImport(ManagedSettings)` / `#if canImport(DeviceActivity)` for Screen Time.
   - Provide stubs/no-ops in mac target where needed (e.g., HardBlockManager stub).
   - Avoid iOS-only view modifiers on macOS (e.g., .preferredColorScheme(.dark) is fine; .tabViewStyle(.page) might not be).

5) **Project structure after split**
   - `MonkShared/` (local package) – shared models, services, utilities, reusable views.
   - `Monk/` (iOS target) – iOS-only views, Screen Time services, Live Activities, paywall UI wrapper, App entry.
   - `MonkMac/` (new macOS target) – macOS App entry, macOS-specific scenes/menus, macOS-only views.
   - Assets: keep common assets in a shared catalog; add mac-specific icons if needed.
   - Rename or relocate the existing `Monk/Shared/` folder to avoid confusion with the `MonkShared` package.

6) **Feature support matrix**
   - **Screen Time / Hard Block**: iOS-only; exclude from mac target.
   - **Live Activities**: iOS-only; exclude from mac target.
   - **RevenueCat**: shared service code; mac target can still use RevenueCat for gating; mac UI may need a mac-appropriate paywall surface.
   - **Calendar integration**: optional on mac; if kept, revisit EventKit usage for macOS or stub.
   - **Notifications**: UNUserNotificationCenter works on both; keep scheduling in shared, permission prompts per platform.
   - **Auth**: keep core logic shared; platform-specific UI (Apple/Google buttons) per target.

7) **UI guidance**
   - iPhone: keep current two-column projects grid.
   - iPad/mac: adaptive grid already implemented; reuse in mac target.
   - mac: prefer sidebar + detail, toolbar items for start/stop, and window resizing; reuse ProjectCard from shared.

8) **Build settings & capabilities**
   - Remove iOS capabilities (FamilyControls, DeviceActivity, Live Activities) from mac entitlements.
   - Add macOS entitlements as needed (notifications, iCloud if SwiftData sync is desired later).
   - Keep SwiftData container/config shared; ensure CloudKit container is available for mac if you enable sync.
   - Do not include iOS extension targets in the mac scheme.

9) **Initial task list to make mac target compile**
   - Create MonkShared package and move shared code.
   - Add macOS target MonkMac; link MonkShared.
   - Move `Monk/Shared/FocusSessionLiveActivity.swift` into the iOS target (or rename that folder) so it is not confused with the `MonkShared` package.
   - Add conditional imports/guards to FocusManager (ActivityKit), HardBlockManager (iOS-only), LiveActivityManager (iOS-only), Screen Time extensions (exclude).
   - Stub any missing types for mac (e.g., HardBlockManager, Haptics, Analytics base properties).
   - Create MonkMacApp.swift with a simple window scene using shared ContentView variant (mac-friendly shell).

10) **Nice-to-have mac polish (later)**
   - Menus/Commands: start/stop session, show history/insights, toggle notifications.
   - Multi-window support for session detail/history.
   - Drag-and-drop for projects; keyboard shortcuts for start/stop.

## Quick answers to the prompt
- **UIKit vs SwiftUI**: SwiftUI.
- **Targets**: Currently a single universal iOS/iPadOS target. Plan: add a separate native macOS SwiftUI target plus a shared Swift package; avoid stuffing Catalyst conditionals everywhere.
- **Where to put #ifs**: Keep Screen Time / ActivityKit imports under `#if os(iOS)` or `#if canImport(...)`; leave them out of the shared package. Shared package stays platform-agnostic.
