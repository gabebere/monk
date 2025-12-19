# Project Progress and Next Steps

This document is a detailed handoff for future sessions with Codex or other agents. It captures what was implemented, how the system is structured, known caveats, and prioritized next actions with acceptance criteria. The codebase is the source of truth; if a feature isn’t listed here, assume it is not implemented.

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
  - Applies a custom shield configuration with the requested copy and actions when enabled.
  - Shield UI now matches Monk’s brand palette and explains the quick-unlock flow; durations pulled from shared constants so UI and logic stay in sync.

- Utilities
  - `Monk/Utilities/DateUtils.swift`: `splitByDay(start:end:)` segments time across day boundaries.
  - `Monk/Utilities/Haptics.swift`: lightweight feedback helpers.

- UI Shell
  - `Monk/ContentView.swift`: TabView with Home, Insights, Settings; lazily constructs `FocusManager` on main actor.
- Home (`Monk/Views/HomeView.swift`):
    - TimerCard with animated CTA and stop button; if not entitled (RevenueCat or synced flag), tap shows paywall; otherwise starts and opens project picker sheet (including “None”).
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
    - Debug card (DEBUG builds only): onboarding preview/reset, purchase reset (clears iCloud entitlement flag, logs in a fresh RevenueCat user, invalidates cache, refreshes).
- Setup checklist (`Monk/Views/SetupChecklistView.swift`):
  - Full-screen checklist shown after paywall close or when entitlement activates.
  - Tasks: login, Screen Time authorization (HardBlock), calendar access with user-selected default calendar, location access for calendar context.
  - Status icons: pending (empty circle), denied (red circle with white X), granted (green circle with check). Persisted via AppStorage flag `shouldShowSetupChecklist`.
- Auth flow:
  - First screen post-install is the redesigned login (matches onboarding gradient). Apple and Google sign-in; optional email capture + newsletter opt-in stored locally (`AuthManager` `newsletterEmail/newsletterOptIn`). After auth, onboarding runs if not yet seen.

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

## RevenueCat Implementation (Current State)

- SDK: purchases-ios 5.51.0 (SPM). RevenueCatUI used for native paywalls.
- API key: Live iOS public key `appl_MdQJjbrjYFxzEaabiQbrRLrmDZc` in `Monk/MonkApp.swift` (logLevel `.debug` in Debug, `.warn` in Release).
- Entitlement: `"Monk Subscription"`.
- Offering: uses `offerings.current` (dashboard default). No hardcoded ID.
- Paywall presentation: `RevenueCatPaywallView` uses `PaywallView(offering: activeOffering)`.
- Gating: Home CTA checks `revenueCat.isPro || entitlementSync.isEntitled`; otherwise shows paywall instead of project picker.
- Entitlement sync: `EntitlementSyncService` mirrors entitlement flag via iCloud KVS (auxiliary, not a replacement for RC validation).
- Debug reset: Settings debug card “Reset purchases (debug)” clears iCloud entitlement flag, logs in a fresh RC user, invalidates cache, refreshes—paywall shows again.
- Debug logging: RevenueCatService logs current offering id, whether paywall is received, and package mappings.
- Reset purchase flow confirmed working after fresh RC login and cache invalidation.

## RevenueCat / IAP To-Do for Submission

- Dashboard
  - Ensure default/current offering (`default`/`monk_subscription`) has a published paywall attached with packages `$rc_monthly` → `monk_monthly`, `$rc_annual` → `monk_annually`.
  - Approve products in App Store Connect (currently READY_TO_SUBMIT per RC warning); set display names to remove “Empty Product titles” warnings.
  - Confirm paywall attaches to the same project/environment as the live key above.

- SDK
  - Keep purchases-ios at 5.51.x (or newer) to support editor paywalls.
  - Clean build folder/reinstall after SDK bumps to avoid stale caches.
- Products are currently READY_TO_SUBMIT; must be approved in App Store Connect and have display names to remove warnings.

- App behavior
  - Verify paywall renders natively (no web/fallback) once RC dashboard is fixed; “RC: paywall received…” should log.
  - Continue gating access via `CustomerInfo.entitlements` (already wired); keep CTA → paywall for non-entitled users.

- Compliance
  - Restore Purchases flow present (RC UI provides Manage Subscriptions; toolbar Close provided).
  - Terms/Privacy links opened from paywall should be mobile-responsive (if hosted).

- Testing checklist
  - Sandbox/Test Store: confirm `offerings.current` is correct, paywall delivered, purchases unlock “Monk Subscription”.
  - Retry “Empty Product titles” after App Store Connect metadata is set.
  - Verify the debug reset returns app to non-entitled and paywall shows on CTA.

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
- Services: `Monk/Services/FocusManager.swift`, `Monk/Services/PaywallManager.swift`, `Monk/Services/EntitlementSyncService.swift`
- Views: `Monk/Views/*` (HomeView, InsightsView, SettingsView, EditSessionView, HistoryView, RevenueCatPaywallView)
- Utilities: `Monk/Utilities/*` (DateUtils, Haptics)
- Tests: `MonkTests/*`

## Next‑Session Kickstart

1) Finalize RevenueCat dashboard: paywall attached to default offering, products approved, display names set; confirm “paywall received” logs.
2) Add a simple Privacy view and telemetry toggle in Settings.
3) Decide if App Intents should return; if so, implement start/stop intents.
4) Add unit tests for FocusManager (start/stop/today) and weekly aggregation.
5) Verify PostHog setup as needed; add a minimal event client if tracking is desired (currently only configured).

After that: decide if iCloud sync moves into v0.1 or stays for v1.0 per SPEC.
