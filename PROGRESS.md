# Project Progress and Next Steps

This document is a detailed handoff for future sessions with Codex or other agents. It captures what was implemented, how the system is structured, known caveats, and prioritized next actions with acceptance criteria.

## Implemented (Detailed)

- Data & Persistence
  - `Monk/Models/FocusSession.swift` (SwiftData `@Model`):
    - Fields: `id: UUID @unique`, `startedAt: Date`, `endedAt: Date?` (nil=in-progress), `moodScore: Int?`, `project: Project?`.
    - Computed: `isInProgress`, `duration` (uses `endedAt ?? Date()`).
  - `Monk/Models/Preferences.swift` (SwiftData `@Model`):
    - Singleton: `id = "singleton"`.
    - Fields: `weeklyGoalHours: Double` (default 40.0), `discardShortSessions: Bool?`.
  - App container: `Monk/MonkApp.swift` sets a shared CloudKit-backed `ModelContainer` (private DB `iCloud.com.gbr.Monk`) so FocusSession/Project/Preferences sync across devices.

- Focus Management (`Monk/Services/FocusManager.swift` – `@MainActor`)
  - Start/Stop with SwiftData persistence; prevents overlapping sessions.
  - Haptics on start/stop (`Monk/Utilities/Haptics.swift`).
  - Today total: recalculates every second while active; correctly clamps sessions that span midnight.
- Soft Blocking (`Monk/Services/SoftBlockManager.swift`, `SoftBlock*` extensions)
  - Manages Screen Time shields for the user-selected set of “soft blocked” apps using ManagedSettings.
  - Applies a custom shield configuration with the requested copy and actions when enabled.
  - Shield UI now matches Monk’s brand palette and explains the quick-unlock flow; durations pulled from shared constants so UI and logic stay in sync.
  - Shield Action and Monitor extensions bootstrap the shared app-group container and persist unlock requests via JSON (`Monk/Shared/SoftBlockUnlockStore.swift`) instead of `UserDefaults`, removing the sandbox warnings.
  - Device Activity entitlements in app + extensions are required; `SoftBlockShieldActionExtension` uses the corrected `com.apple.familycontrols.shield-actions` identifier so the unlock handler can load.

- Utilities
  - `Monk/Utilities/DateUtils.swift`: `splitByDay(start:end:)` segments time across day boundaries.
  - `Monk/Utilities/Haptics.swift`: lightweight feedback helpers.

- UI Shell
  - `Monk/ContentView.swift`: TabView with Home, Insights, Settings; lazily constructs `FocusManager` on main actor.
- Home (`Monk/Views/HomeView.swift`):
    - TimerCard with animated CTA and stop button; starting now opens a project picker sheet (including “None”).
    - Completed Session sheet (`CompletedSessionView`): celebrate, assign project, capture mood.
    - Edit Session sheet (`Monk/Views/EditSessionView.swift`): view timing, adjust project, adjust mood.
    - Projects section: grid of project cards ordered by recent activity, quick create button, detail sheet with rename, hard blocking, and delete.
    - Live Activity support: starting a session spins up an ActivityKit live activity (after adding the Live Activities widget extension) and ends it when the session stops.
- Insights (`Monk/Views/InsightsView.swift`):
    - Landing grid: compact two-column cards (plus full-width weekly-goal tile) highlighting weekly totals, satisfaction, consistency, prime hours, and rhythm with a palette keyed to the home gradient.
    - Tapping any tile pushes a gradient-matched detail view with haptic-enabled week selector, Swift Charts visualisations, and historical context tuned for quick scanning.
    - `InsightSnapshot` helper and reusable analyzer hooks pave the way for widget targets and lock-screen surfaces.
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

2) Screen Time capabilities & entitlements
- Enable FamilyControls, ManagedSettings, DeviceActivity, and App Groups on the app target and every Screen Time extension (Shield UI, Shield Actions, Monitor, DeviceActivity report).
- Users must grant Screen Time access the first time soft blocking is configured.
- Ensure provisioning profiles include the `com.apple.familycontrols.shield-actions` entitlement so the quick-unlock handler can load.

3) Live Activities
- Enable Background Modes → Remote notifications for the app target, add the `activitykit` entitlement, and create a WidgetKit extension for `MonkLiveActivities`.

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
  - Home → Start; choose project; Stop → Today total updates; Insights Weekly bar updates immediately.

- Insights
  - Daily: choose a date; verify the timeline capsule highlights focused periods accurately.
  - Weekly: switch between 7/14 days; confirm totals and streak count; tap a bar (iOS 17+) to view the day’s sessions.

- Session wrap-up
  - Stop an in-progress session → CompletedSessionView appears; assign a project + mood; saving persists and updates Insights.
- Cloud sync
  - Run the app on two devices/simulators logged into the same iCloud account; create/edit sessions/projects and confirm changes replicate.
- Live Activity visible in Dynamic Island / Lock Screen
  - After adding the `MonkLiveActivities` WidgetKit extension in Xcode, start a session on device (iOS 16.2+) and confirm the live activity appears and updates.

## Temporal Insights Roadmap

### Phase 1 — MVP (shipped)
- Temporal summary card (total focus time, session count, satisfaction, streak).
- Best Focus Window detection (2-hour rolling window, duration × satisfaction scoring).
- Time-of-day bar chart (hourly aggregation with highlight for the best window).
- Duration-weighted mood averages to ground all copy in recorded satisfaction.

### Phase 2 — Correlations & Trends
- Add weekly/monthly trend charts for focus hours, session counts, and satisfaction.
- Compute consistency indices (stddev of start times and daily totals) and streak callouts.
- Chart satisfaction vs. duration/time-of-day correlations with descriptive copy.
- Acceptance: Insights tab surfaces at least two correlation views, all calculations back SwiftData sessions, and empty-state messaging covers sparse data.

### Phase 3 — Contextual & Predictive Insights
- Project-level insights (time allocation, satisfaction, efficiency score).
- Weekly summary cards (total time, average satisfaction, top project, best day) reusable for notifications/widgets.
- Forecasting hooks (predictive “try this next” recommendations, fatigue detector scaffolding).
- Acceptance: Summary cards and project analytics available in UI, predictive surfaces pull from a reusable analyzer API, and all user-facing copy reflects on-device calculations.

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
- Day Detail: richer session metadata (mood, project, duration) and quick actions.
- AC: Daily view usable on iOS 16; Day Detail exposes mood/project info and navigation works without overlay APIs.

5) Project dashboards
- Flesh out the project detail view (blocking configuration, per-session history, editing).
- AC: Detail screen shows project timeline, lets users toggle project-specific soft blocking.

6) Quick unlock stability
- Verify the shield action extension schedules Device Activity successfully on device (needs entitlement + profiles regenerated after identifier fix).
- AC: Tapping “Unlock briefly” triggers the 20s wait/120s unlock window; monitor logs show `Scheduled DeviceActivity…` without ManagedSettings errors.

7) Live Activity widget target
- Add a WidgetKit extension (`MonkLiveActivities`) and wire `MonkLiveActivities.swift` + Info.plist to that target so the ActivityKit configuration renders.
- AC: Widget extension builds; live activity renders on Lock Screen and Dynamic Island.

8) Temporal insights expansion (Phase 2)
- Add correlation charts, variability metrics, and trend summaries from Phase 2 above.
- AC: Time-of-day and trend charts cross-link, calculated metrics match CSV spot checks, and empty states cover <3 sessions.

9) Predictive insights scaffolding (Phase 3)
- Build analyzer hooks for project-based and forecast insights described above.
- AC: Analyzer returns stubs for forecasts, summary cards render from live data, and push/notification copy can reuse the generated payloads.

10) Testing expansion
- Add unit tests:
  - FocusManager: start/stop invariants, today total across midnight.
  - Aggregation: weekly totals, streak logic, daily timeline segmentation (including DST boundaries).
  - InsightsAnalyzer: hourly bucketing, best-window ranking, satisfaction weighting.
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
