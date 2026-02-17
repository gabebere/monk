# Monk Production Progress

Last updated: 2026-02-16

This document is the operational handoff for agents/developers working on Monk. It describes the current implementation, where logic lives, and what is required to reach production-level quality.

## 1) Product status (current)

- App model: paid app (no in-app subscription/paywall runtime logic in current app flow).
- Platform: iOS app built with SwiftUI + SwiftData.
- Core user loop: authenticate -> complete setup checklist/onboarding -> start/stop focus sessions -> review insights/history -> manage projects/tasks/settings.
- Data + sync:
  - SwiftData `ModelContainer` with CloudKit private DB (`iCloud.com.gbr.Monk`) and local fallback.
  - Optional cross-device session mirroring through CloudKit custom records (`SessionMirrorEvent`).
  - App Group snapshot (`group.com.gbr.Monk`) used by widgets/live activities/shield extension.

## 2) Targets and extension boundaries

### App target
- `Monk`: primary iOS app.

### Extension targets
- `HardBlockShieldUIExtension`: custom Screen Time shield UI.
- `MonkLiveActivitiesExtension`: Live Activity + weekly goal widget.
- `DeviceActivity`: report extension scaffold (currently basic template/stub usage).

## 3) Runtime architecture and flow

### Launch/bootstrap
- `Monk/MonkApp.swift`
  - Bootstraps hard-block state store.
  - Configures analytics + UserJot.
  - Sets mirror service model container.
  - Creates CloudKit-backed SwiftData container with fallback.
  - Registers for remote notifications.
- `Monk/ContentView.swift`
  - Root gate for auth + setup checklist + onboarding.
  - Builds main tab shell (`home`, `projects` conditional, `history`, `settings`).
  - Creates and injects `FocusManager`.
  - Triggers health sync when app becomes active.

### Focus session lifecycle
- `Monk/Services/FocusManager.swift`
  - Starts/stops sessions.
  - Recalculates today total in real-time.
  - Handles discard-short-session policy.
  - Applies/removes hard blocks by project.
  - Emits mirror start/stop events.
  - Writes snapshot for extensions.
  - Logs location + calendar events after stop.
- `Monk/Services/LiveActivityManager.swift`
  - Starts/updates/ends ActivityKit live activity for active session.

### Persistence and domain modeling
- SwiftData models:
  - `Monk/Models/FocusSession.swift`
  - `Monk/Models/Project.swift`
  - `Monk/Models/FocusTask.swift`
  - `Monk/Models/Preferences.swift`
  - `Monk/Models/HealthSampleLink.swift`
  - `Monk/Models/TaskRecurrence.swift`
- Save safety helper:
  - `Monk/Utilities/ModelContext+Persistence.swift` (`saveOrRollback`).

### Cross-device mirroring
- `Monk/Services/MirrorSyncService.swift`
  - Creates/maintains CloudKit query subscription (`session-mirror-events`) for silent pushes.
  - Emits session start/stop mirror records.
  - Handles remote notifications and rehydrates local SwiftData session state.
  - Deduplicates processed mirror events.
  - Posts `.mirrorSessionDidChange` to update in-app state.

### Screen Time blocking
- `Monk/Services/HardBlockManager.swift`
  - Requests FamilyControls authorization.
  - Applies/removes shields via `ManagedSettingsStore`.
  - Persists current shield selection in App Group file.
- `HardBlockShieldExtension/HardBlockShieldDataSource.swift`
  - Renders custom shield UI shown when blocked apps/domains are opened.

### Calendar/location/health integrations
- `Monk/Services/CalendarIntegration.swift`
  - Calendar access + list writable calendars.
  - Upserts Monk focus events.
  - Backfills/purges Monk events.
  - Upserts/deletes imported health events.
- `Monk/Services/LocationProvider.swift`
  - Requests one-shot location + reverse geocodes display name.
- `Monk/Services/HealthSyncService.swift`
  - HealthKit read auth.
  - Imports workouts + sleep windows into calendar.
  - Tracks imported samples in `HealthSampleLink`.

### Auth and identity
- `Monk/Services/AuthManager.swift`
  - Apple Sign In + Google Sign-In + debug-only password auth path.
  - Persists auth state in `UserDefaults`.
  - Newsletter preference state.

### Analytics and feedback
- `Monk/Utilities/AnalyticsService.swift`
  - PostHog setup, identify/reset, telemetry toggle, event capture.
- `Monk/Utilities/UserJotClient.swift`
  - UserJot helper wrappers (SDK-gated).
- `Monk/Utilities/UserJotSigner.swift`
  - Generates UserJot signature only if `USERJOT_IDENTITY_SECRET` is provided via env or Info.plist.
- `Monk/Views/FeedbackWebView.swift`
  - Embedded WKWebView wrapper for feedback widget.

## 4) File map (app target)

### Root/config
- `Monk/MonkApp.swift`: app entry, container wiring, push registration.
- `Monk/ContentView.swift`: root app state machine + tab shell.
- `Monk/Info.plist`: URL schemes, background mode, health usage text.
- `Monk/Monk.entitlements`: CloudKit, App Group, HealthKit, FamilyControls.
- `Monk/IAP.storekit`: local StoreKit config placeholder file.

### Services
- `Monk/Services/FocusManager.swift`
- `Monk/Services/InsightsAnalyzer.swift`
- `Monk/Services/AuthManager.swift`
- `Monk/Services/HardBlockManager.swift`
- `Monk/Services/MirrorSyncService.swift`
- `Monk/Services/CalendarIntegration.swift`
- `Monk/Services/CalendarSelectionSyncService.swift` (legacy no-op compatibility stub)
- `Monk/Services/HealthSyncService.swift`
- `Monk/Services/LocationProvider.swift`
- `Monk/Services/LiveActivityManager.swift`

### Models
- `Monk/Models/FocusSession.swift`
- `Monk/Models/Project.swift`
- `Monk/Models/FocusTask.swift`
- `Monk/Models/Preferences.swift`
- `Monk/Models/HealthSampleLink.swift`
- `Monk/Models/TaskRecurrence.swift`

### Shared snapshot + activity contracts
- `Monk/Shared/FocusSessionLiveActivity.swift`
- `Monk/Shared/Snapshot/LiveSnapshot.swift`
- `Monk/Shared/Snapshot/SnapshotReader.swift`
- `Monk/Shared/Snapshot/SnapshotWriter.swift`

### Utilities
- `Monk/Utilities/AnalyticsService.swift`
- `Monk/Utilities/UserJotClient.swift`
- `Monk/Utilities/UserJotSigner.swift`
- `Monk/Utilities/ModelContext+Persistence.swift`
- `Monk/Utilities/FeatureFlags.swift`
- `Monk/Utilities/DateUtils.swift`
- `Monk/Utilities/FocusSession+Calendar.swift`
- `Monk/Utilities/Haptics.swift`
- `Monk/Utilities/ConfettiView.swift`
- `Monk/Utilities/AppTab.swift`

### Design and views
- `Monk/Design/Theme.swift`: gradients/visual tokens + animated background.
- Auth/onboarding/setup:
  - `Monk/Views/AuthGatewayView.swift`
  - `Monk/Views/SetupChecklistView.swift`
  - `Monk/Views/OnboardingStoryView.swift`
- Primary product surfaces:
  - `Monk/Views/HomeView.swift`
  - `Monk/Views/InsightsView.swift`
  - `Monk/Views/HistoryView.swift`
  - `Monk/Views/SettingsView.swift`
- Projects:
  - `Monk/Views/Projects/ProjectsTabView.swift`
  - `Monk/Views/Projects/ProjectGridListView.swift`
  - `Monk/Views/Projects/ProjectDisplayModels.swift`
- Tasks:
  - `Monk/Views/Tasks/ScheduledTasksView.swift`
  - `Monk/Views/Tasks/ScheduledTaskRow.swift`
  - `Monk/Views/Tasks/TaskEditorView.swift`
  - `Monk/Views/Tasks/WeekdayPicker.swift`
- Session support:
  - `Monk/Views/EditSessionView.swift`
  - `Monk/Views/CalendarPreviewCard.swift`
  - `Monk/Views/MoodSlider.swift`
  - `Monk/Views/FeedbackWebView.swift`

## 5) External dependencies currently linked

- `PostHog` (analytics)
- `UserJot` (feedback)
- `GoogleSignIn` (+ transitive auth libs)

## 6) Production hardening status

### Completed in this cleanup pass
- Removed duplicate analytics SDK setup path from app delegate.
- Replaced remaining ad-hoc `print` usage with `OSLog` in app code paths.
- Removed deprecated `UserDefaults.synchronize()` usage.
- Reduced sensitive logging verbosity (notification token + analytics id handling).
- Made analytics configure path idempotent.
- Eliminated embedded UserJot signing secret from source; now loaded from env/Info.plist when provided.
- Restricted password login account path to `DEBUG` builds only.
- Fixed auth persistence edge case where nil name/email could leave stale values.
- Improved mirror subscription management to avoid unnecessary delete/recreate churn on launch.
- Fixed mirror shield-failure notification copy to reflect failure state accurately.
- Added calendar integration error logging in previously silent catch paths.

### Known risks and gaps (remaining)

#### P0 (before release)
- Move runtime configuration constants to build config/xcconfig where appropriate:
  - PostHog API key/host (`Monk/Utilities/AnalyticsService.swift`)
  - UserJot project id (`Monk/MonkApp.swift`, `Monk/Views/SettingsView.swift`)
- Add real test targets and baseline automated tests (unit + UI smoke); project currently has no test targets.
- Define clear release policy for debug-only tooling visibility in settings/onboarding flows.

#### P1 (next)
- Add retry/backoff/error surfacing strategy for CloudKit mirror and calendar sync failures.
- Add data migration notes/versioning strategy for SwiftData model evolution.
- Centralize feature/config flags to avoid scattering raw `UserDefaults` keys.

#### P2 (later)
- Expand observability: structured event taxonomy + failure dashboards.
- Tighten extension contract documentation (snapshot schema/versioning guarantees).
- Add architecture decision records (ADRs) for auth model, sync model, and privacy model.

## 7) Notes for agents working in parallel

- UI polish work is actively happening in parallel. Avoid modifying the same UI files unless coordinated.
- For infra/production hardening work, prioritize:
  1. services,
  2. utilities,
  3. configuration,
  4. tests/tooling.
- Keep this file updated whenever architecture, dependencies, or release risks change.
