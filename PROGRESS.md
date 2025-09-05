# Project Progress and Next Steps

This document is a detailed handoff for future sessions with Codex or other agents. It captures what was implemented, how the system is structured, known caveats, and prioritized next actions with acceptance criteria.

## Implemented (Detailed)

- Data & Persistence
  - `Monk/Models/FocusSession.swift` (SwiftData `@Model`):
    - Fields: `id: UUID @unique`, `startedAt: Date`, `endedAt: Date?` (nil=in‑progress), `note: String?`, `tags: [String]`.
    - Computed: `isInProgress`, `duration` (uses `endedAt ?? Date()`).
  - `Monk/Models/Preferences.swift` (SwiftData `@Model`):
    - Singleton: `id = "singleton"`.
    - Fields: `dailyGoalHours: Double` (default 4.0), `nudgeMinutes: Int?` (default 50), `iCloudSyncEnabled: Bool`.
  - App container: `Monk/MonkApp.swift` sets a shared `ModelContainer` with both models (`ModelConfiguration(isStoredInMemoryOnly: false)`).

- Focus Management (`Monk/Services/FocusManager.swift` – `@MainActor`)
  - Start/Stop with SwiftData persistence; prevents overlapping sessions.
  - Haptics on start/stop (`Monk/Utilities/Haptics.swift`).
  - Nudges: schedules a one‑off local notification based on `Preferences.nudgeMinutes`; cancels on stop.
  - Live Activities: starts/ends (ActivityKit) on start/stop; recreates on relaunch if a session is in progress.
  - Today total: recalculates every second while active; correctly clamps sessions that span midnight.
  - App Group summary: writes `todayHours` and `last7` totals to shared defaults; calls `WidgetCenter.reloadTimelines` for the Summary widget.

- Utilities
  - `Monk/Utilities/DateUtils.swift`: `splitByDay(start:end:)` segments time across day boundaries.
  - `Monk/Utilities/CSVExporter.swift`: CSV builder (id, started, ended, duration_s, tags, note) + timestamped filename.
  - `Monk/Utilities/AppGroupBridge.swift`: writes Summary payload to `UserDefaults(suiteName:)`.
  - `Monk/Utilities/ActivityView.swift`: UIActivityViewController wrapper for exports.

- UI Shell
  - `Monk/ContentView.swift`: TabView with Home, Insights, Settings; lazily constructs `FocusManager` on main actor.
  - Home (`Monk/Views/HomeView.swift`):
    - TimerCard (monospaced ticking), Start/Stop, optional note on start.
    - TodayTotal (monospaced hours), RecentSessions list (last 5).
    - Edit Session sheet (`Monk/Views/EditSessionView.swift`):
      - Edit note; add/remove tag chips; immediate persistence on changes.
  - Insights (`Monk/Views/InsightsView.swift`):
    - Mode toggle: Daily | Weekly.
    - Tag filter chips (left‑aligned, horizontal scroll).
    - Daily view:
      - Stacked per‑hour bars by tag; fixed y‑axis 0–60 minutes.
      - 16‑hour carousel pages: 0–16 and 8–24 for smoother browsing.
      - Minutes are apportioned evenly across tags if a session has multiple tags; untagged → “Untagged”.
    - Weekly view:
      - Total hours per day (7 or 14 days), with optional goal RuleMark.
      - Streak count based on `dailyGoalHours` (consecutive days ≥ goal).
      - Tap bar to open a Day Detail sheet (iOS 17+ overlay); shows sessions, notes, tags and per‑day duration.
  - Settings (`Monk/Views/SettingsView.swift`):
    - Daily goal (Stepper), nudges (Off/25/50/90), iCloud toggle placeholder.
    - Export CSV… sheet with range options (All, last 7, last 30); timestamped filename; share sheet.

- Widgets & Live Activities (Code Scaffolding)
  - Summary widget: `MonkWidgets/MonkSummaryWidget.swift` reads App Group summary (today and 7‑day trend).
  - Live Activity: `Monk/Shared/FocusAttributes.swift` + `MonkWidgets/MonkLiveActivityWidget.swift` templates.
  - Widget bundle: `MonkWidgets/MonkWidgetsBundle.swift`.

- Shortcuts (App Intents): `Monk/AppIntents/DeepWorkIntents.swift`
  - `StartDeepWorkIntent`, `StopDeepWorkIntent` (uses SwiftData container internally; starts/ends Live Activity when available).
  - Gallery tiles were removed due to SDK signature differences; actions still discoverable via Shortcuts search.

- Tests
  - `MonkTests/DateUtilsTests.swift`: verifies midnight split (30m before and after midnight).

## Configuration Required in Xcode

1) App Groups (for widget data)
- Create an App Group ID (e.g., `group.com.yourcompany.Monk`).
- Add the capability to BOTH targets (App + Widget) and check the same group.
- Update code:
  - `Monk/Utilities/AppGroupBridge.swift` → `suiteName`.
  - `MonkWidgets/MonkSummaryWidget.swift` → `UserDefaults(suiteName:)`.

2) Live Activities
- App target → Signing & Capabilities → add “Live Activities”.
- Add a Widget Extension target if not present (we added code files under `MonkWidgets/`, but creating the actual target is done in Xcode). Include:
  - `MonkWidgets/MonkWidgetsBundle.swift`
  - `MonkWidgets/MonkSummaryWidget.swift`
  - `MonkWidgets/MonkLiveActivityWidget.swift`
  - `Monk/Shared/FocusAttributes.swift`

3) App Intents
- App target → Signing & Capabilities → add “App Intents”.
- Build/run once; in Shortcuts app, search for “Start Deep Work” / “Stop Deep Work”.
- If you require Shortcuts Gallery tiles, re‑add an `AppShortcutsProvider` matching your SDK (see “Known SDK differences”).

4) Deployment targets
- Recommended iOS 17+ (required for Charts overlay selection and smoother Live Activities/testing).
- iOS 16 is supported for core timing; chart tap‑to‑select falls back to no overlay.

## Known SDK Differences / Notes

- AppShortcutsProvider signature differs by SDK:
  - Some SDKs expect `appShortcuts: AppShortcut` (single), others `[AppShortcut]`.
  - iOS 17 deprecates the older initializer and requires `shortTitle` + `systemImageName`.
  - We removed providers to avoid build breaks. Actions still work via search. Re‑add providers once Xcode/iOS SDK is confirmed.
- Swift Charts APIs:
  - Use `proxy.plotFrame` (optional) on iOS 17+; unwrap before use.
  - `chartXScale(domain:)` expects `ClosedRange<Date>` for date axes.
  - Avoid `.position(by:)` where possible to keep type‑checking fast.

## Usage & Validation (Manual QA)

- Start/Stop flow
  - Home → Start (optional note), lock screen shows Live Activity (once widget target is added), gentle nudge at set cadence.
  - Stop → Today total updates; Insights Weekly bar updates immediately.

- Insights
  - Daily (default): pick a date; swipe between pages; verify stacked minutes by tag; y‑axis 0–60 min.
  - Weekly: switch to 7/14; confirm totals and streak count; tap a bar (iOS 17+) to view the day’s sessions.

- Tags & notes
  - Home → tap a Recent Session → edit note; add/remove tags; changes persist.

- CSV export
  - Settings → Export CSV… → pick range → Export → open in Numbers/Sheets; check columns and timestamps.

- Widgets (after App Group configured)
  - Run app to write summary; check widget shows today and 7‑day trend; verify it refreshes within a few minutes or after start/stop.

## Remaining Work (Prioritized with Acceptance Criteria)

1) Wire Widget Extension & App Group
- Create the Widget Extension target and include provided files.
- Enable App Groups on both targets; set IDs in code.
- AC: Summary widget shows real today hours and last 7 trend; updates within 5 minutes or after timeline reload.

2) Live Activity polish
- Ensure Live Activity displays on Lock Screen/Dynamic Island with elapsed monospaced timer.
- Add icons/branding if desired; confirm end on Stop.
- AC: Start shows activity within 1s; Stop dismisses immediately.

3) Privacy view + telemetry toggle (spec requirement)
- Add a Privacy screen under Settings with clear copy; toggle for telemetry (default Off).
- No telemetry is currently sent; implementing would require endpoint + consent gate.
- AC: Toggle persists; privacy text present; no network when Off.

4) Shortcuts Gallery (optional)
- Re‑introduce `AppShortcutsProvider` based on exact SDK:
  - iOS 17+: `[AppShortcut]` with `shortTitle` + `systemImageName`.
  - iOS 16: single `AppShortcut` without those fields.
- AC: Two tiles appear (“Start”, “Stop”) in Shortcuts → App Shortcuts.

5) iCloud sync (deferred to v1.0 in spec)
- Configure SwiftData CloudKit; guard by preference.
- AC: Enabling sync mirrors sessions and preferences across devices; last‑writer‑wins for edits; no duplicates on re‑create.

6) Insights polish
- iOS 16 daily selection fallback (e.g., segmented hour ranges without overlay).
- Day Detail: tag filter + inline note/tag edits.
- AC: Daily view usable on iOS 16; Day Detail can filter tags.

7) Tag UX enhancements
- Suggestions from existing tags; normalize input (lowercase, trim, no spaces or replace with dashes).
- AC: Adding from suggestions works; duplicates prevented; consistent formatting.

8) Testing expansion
- Add unit tests:
  - FocusManager: start/stop invariants, today total across midnight, nudge scheduling cancelation.
  - Aggregation: weekly totals, streak logic, hourly tag binning (including multi‑tag splits, DST boundaries).
  - CSVExporter: escaping, ordering, ranges.
- AC: Tests pass locally; cover critical logic paths.

## Architecture Map (Quick Reference)

- App entry: `Monk/MonkApp.swift`
- Models: `Monk/Models/*`
- Services: `Monk/Services/FocusManager.swift`, `LiveActivityManager.swift`
- Views: `Monk/Views/*` (HomeView, InsightsView, SettingsView, EditSessionView)
- Utilities: `Monk/Utilities/*` (DateUtils, CSVExporter, Haptics, AppGroupBridge, ActivityView)
- Widgets: `MonkWidgets/*` + `Monk/Shared/FocusAttributes.swift`
- App Intents: `Monk/AppIntents/DeepWorkIntents.swift`
- Tests: `MonkTests/*`

## Next‑Session Kickstart

1) Configure App Group ID and add Widget Extension target; verify Summary widget shows real data.
2) Add a simple Privacy view and telemetry toggle in Settings.
3) Re‑introduce Shortcuts Gallery providers for your Xcode/iOS SDK.
4) Add unit tests for FocusManager (start/stop/today) and weekly aggregation.

After that: decide if iCloud sync moves into v0.1 or stays for v1.0 per SPEC.

## Widget Wiring Checklist (App Group + Widget Target)

1) Set a real App Group ID
   - Open `Monk/Shared/AppGroup.swift` and set `AppGroup.id` to your identifier (e.g., `group.com.yourcompany.Monk`).

2) Enable capabilities in Xcode
   - App target → Signing & Capabilities → add “App Groups” and check the same ID.
   - Widget Extension target (created in step 3) → also add “App Groups” and check the same ID.

3) Create the Widget Extension target
   - In Xcode: File → New → Target… → Widget Extension.
   - Include these files in the Widget target (Target Membership):
     - `MonkWidgets/MonkWidgetsBundle.swift`
     - `MonkWidgets/MonkSummaryWidget.swift`
     - `MonkWidgets/MonkLiveActivityWidget.swift` (optional for Live Activities)
     - `Monk/Shared/FocusAttributes.swift` (for Live Activities)
     - `Monk/Shared/AppGroup.swift` (so the widget shares the App Group constant)

4) Verify data flow
   - Run the app and start/stop a session to trigger summary writes.
   - `FocusManager` writes `todayHours` and `last7` to `UserDefaults(suiteName: AppGroup.id)` and calls `WidgetCenter.reloadTimelines`.
   - `MonkSummaryWidget` reads the same key and shows today + 7‑day trend.

5) Refresh behavior (Acceptance)
   - Timeline policy is 5 minutes; manual reloads occur on start/stop.
   - Acceptance: Today total and 7‑day trend populate and refresh within 5 minutes or immediately after a start/stop.

Troubleshooting
   - If the widget shows placeholders: confirm Target Membership for the shared files and matching App Group IDs on both targets.
   - Simulator sometimes caches timelines; use `WidgetCenter.shared.reloadAllTimelines()` from a debug button if needed.
