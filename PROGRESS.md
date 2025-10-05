# Project Progress and Next Steps

This document is a detailed handoff for future sessions with Codex or other agents. It captures what was implemented, how the system is structured, known caveats, and prioritized next actions with acceptance criteria.

## Implemented (Detailed)

- Data & Persistence
  - `Monk/Models/FocusSession.swift` (SwiftData `@Model`):
    - Fields: `id: UUID @unique`, `startedAt: Date`, `endedAt: Date?` (nil=in‑progress), `note: String?`, `tags: [String]`.
    - Computed: `isInProgress`, `duration` (uses `endedAt ?? Date()`).
    - Mood: optional `moodScore` (0 = bad, 1 = neutral, 2 = good).
  - `Monk/Models/Preferences.swift` (SwiftData `@Model`):
    - Singleton: `id = "singleton"`.
    - Fields: `weeklyGoalHours: Double` (default 40.0), `discardShortSessions: Bool?`.
  - App container: `Monk/MonkApp.swift` sets a shared `ModelContainer` with both models (`ModelConfiguration(isStoredInMemoryOnly: false)`).

- Focus Management (`Monk/Services/FocusManager.swift` – `@MainActor`)
  - Start/Stop with SwiftData persistence; prevents overlapping sessions.
  - Haptics on start/stop (`Monk/Utilities/Haptics.swift`).
  - Today total: recalculates every second while active; correctly clamps sessions that span midnight.
- Soft Blocking (`Monk/Services/SoftBlockManager.swift`)
  - Manages Screen Time shields for the user-selected set of “soft blocked” apps using ManagedSettings.
  - Applies a custom shield configuration with the requested copy and actions when enabled.

- Utilities
  - `Monk/Utilities/DateUtils.swift`: `splitByDay(start:end:)` segments time across day boundaries.
  - `Monk/Utilities/Haptics.swift`: lightweight feedback helpers.

- UI Shell
  - `Monk/ContentView.swift`: TabView with Home, Insights, Settings; lazily constructs `FocusManager` on main actor.
  - Home (`Monk/Views/HomeView.swift`):
    - TimerCard (monospaced ticking), Start/Stop, optional note on start.
    - TodayTotal (monospaced hours), RecentSessions list (last 5).
    - Edit Session sheet (`Monk/Views/EditSessionView.swift`):
      - Edit note; add/remove tag chips; immediate persistence on changes.
      - Session mood slider (Bad ↔ Neutral ↔ Good) stored per session.
  - Insights (`Monk/Views/InsightsView.swift`):
    - Mode toggle: Daily | Weekly.
    - Tag filter chips (left‑aligned, horizontal scroll).
    - Daily view:
      - Stacked per‑hour bars by tag; fixed y‑axis 0–60 minutes.
      - 16‑hour carousel pages: 0–16 and 8–24 for smoother browsing.
      - Minutes are apportioned evenly across tags if a session has multiple tags; untagged → “Untagged”.
    - Weekly view:
      - Total hours per day (7 or 14 days), with optional goal RuleMark derived from weekly goal.
      - Streak count based on weekly goal (consecutive weeks ≥ goal).
      - Tap bar to open a Day Detail sheet (iOS 17+ overlay); shows sessions, notes, tags and per‑day duration.
- Settings (`Monk/Views/SettingsView.swift`):
    - Weekly goal picker (wheel), discard-short toggle.
    - Soft-block toggle and FamilyActivityPicker integration for choosing apps to shield.

- Shortcuts: Not implemented (App Intents removed in current build).
  - Gallery tiles were removed due to SDK signature differences; actions still discoverable via Shortcuts search.

- Tests
  - `MonkTests/DateUtilsTests.swift`: verifies midnight split (30m before and after midnight).

## Configuration Required in Xcode

1) Shortcuts integration (optional)
- Reintroduce App Intents if Siri/Shortcuts automation is desired.
- Requires adding the capability and rebuilding the intents module.

2) Screen Time capabilities
- Enable FamilyControls, ManagedSettings, and DeviceActivity in the app target.
- Users must grant Screen Time access the first time soft blocking is configured.

3) Deployment targets
- Recommended iOS 17+ (required for Charts overlay selection).
- iOS 16 is supported for core timing; chart tap-to-select falls back to no overlay.

## Known SDK Differences / Notes

- Swift Charts APIs:
  - Use `proxy.plotFrame` (optional) on iOS 17+; unwrap before use.
  - `chartXScale(domain:)` expects `ClosedRange<Date>` for date axes.
  - Avoid `.position(by:)` where possible to keep type‑checking fast.

## Usage & Validation (Manual QA)

- Start/Stop flow
  - Home → Start (optional note); Stop → Today total updates; Insights Weekly bar updates immediately.

- Insights
  - Daily (default): pick a date; swipe between pages; verify stacked minutes by tag; y‑axis 0–60 min.
  - Weekly: switch to 7/14; confirm totals and streak count; tap a bar (iOS 17+) to view the day’s sessions.

- Tags & notes
  - Home → tap a Recent Session → edit note; add/remove tags; changes persist.

## Remaining Work (Prioritized with Acceptance Criteria)

1) Privacy view + telemetry toggle (spec requirement)
- Add a Privacy screen under Settings with clear copy; toggle for telemetry (default Off).
- No telemetry is currently sent; implementing would require endpoint + consent gate.
- AC: Toggle persists; privacy text present; no network when Off.

2) Shortcuts (optional)
- Re-introduce App Intents and/or `AppShortcutsProvider` when automation is needed.
- AC: Start/Stop accessible via Shortcuts once re-added.

3) iCloud sync (deferred to v1.0 in spec)
- Configure SwiftData CloudKit; guard by preference.
- AC: Enabling sync mirrors sessions and preferences across devices; last‑writer‑wins for edits; no duplicates on re‑create.

4) Insights polish
- iOS 16 daily selection fallback (e.g., segmented hour ranges without overlay).
- Day Detail: tag filter + inline note/tag edits.
- AC: Daily view usable on iOS 16; Day Detail can filter tags.

5) Tag UX enhancements
- Suggestions from existing tags; normalize input (lowercase, trim, no spaces or replace with dashes).
- AC: Adding from suggestions works; duplicates prevented; consistent formatting.

6) Testing expansion
- Add unit tests:
  - FocusManager: start/stop invariants, today total across midnight.
  - Aggregation: weekly totals, streak logic, hourly tag binning (including multi‑tag splits, DST boundaries).
- AC: Tests pass locally; cover critical logic paths.

## Architecture Map (Quick Reference)

- App entry: `Monk/MonkApp.swift`
- Models: `Monk/Models/*`
- Services: `Monk/Services/FocusManager.swift`
- Views: `Monk/Views/*` (HomeView, InsightsView, SettingsView, EditSessionView, HistoryView)
- Utilities: `Monk/Utilities/*` (DateUtils, Haptics)
- Tests: `MonkTests/*`

## Next‑Session Kickstart

1) Add a simple Privacy view and telemetry toggle in Settings.
2) Decide if App Intents should return; if so, implement start/stop intents.
3) Add unit tests for FocusManager (start/stop/today) and weekly aggregation.

After that: decide if iCloud sync moves into v0.1 or stays for v1.0 per SPEC.
