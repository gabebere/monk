  Deep Work Tracker — Product & Technical Spec (v0.1)

iOS app that tracks “Deep Work” hours akin to Apple Watch Sleep: simple start/stop, live lock-screen timer, rich weekly insights, and privacy-first on‑device data. Includes a smooth dev workflow using the OpenAI CLI (Codex) alongside Xcode.

⸻

1) Product Overview

Problem: Knowledge workers struggle to protect deep-focus time and to see honest trends (hours/day, streaks).

Solution: A SwiftUI iOS app with one‑tap Start/Stop, a Live Activity timer on the Lock Screen/Dynamic Island, daily & weekly charts, realistic goals, gentle nudges, and optional iCloud sync.

Success metrics (v1)
    •    D1 activation: ≥60% complete ≥1 session after install
    •    Median daily deep‑work time (active users): ≥2.5 h
    •    Day‑7 retention: ≥30%
    •    Weekly goal attainment rate: 3 of 7 days for ≥40% of active users

Non‑goals (v1)
    •    Automatic detection from device usage (Screen Time)
    •    Cross‑platform (macOS, watchOS, Android)
    •    Team/manager dashboards

⸻

2) Personas & Jobs‑to‑be‑Done (JTBD)
    1.    Student: “When I sit to study, I want a clean timer and weekly proof I’m consistent, so I can feel progress and pass exams.”
    2.    Engineer/Founder: “When I time block mornings, I want frictionless Start/Stop and a Lock Screen timer so I avoid context switching.”
    3.    Researcher/Writer: “When planning a draft week, I want goal lines and streaks so I stay accountable without sharing my data.”

⸻

3) User Stories & Acceptance Criteria

Core timing
    •    Start a session: As a user I can tap Start to begin logging; a timer appears in‑app and as a Live Activity.
AC: Start inserts a FocusSession with startedAt=now, endedAt=nil. Live Activity shows elapsed time. Notification permission requested once.
    •    Stop a session: Tap Stop to finalize.
AC: Session saved with endedAt=now. Live Activity ends immediately.
    •    Gentle nudge: While a session runs, receive a one‑off notification (e.g., after 50 min) asking whether to log a break.
AC: Scheduled on start; cancelled on stop.

Insights
    •    Today total: See today’s accumulated deep‑work time.
AC: Sum of durations where startOfDay(startedAt) == today.
    •    Weekly chart: View a bar chart of the last 7–14 days in hours.
AC: Each bar = total daily hours; includes optional goal RuleMark.
    •    Streaks: Show consecutive days at/above a daily goal.
AC: Consecutive day count increments when daily total ≥ goal.

Organization
    •    Notes: Optionally add a short note at start/stop.
AC: note persisted and editable post‑hoc.
    •    Tags: Apply tags (e.g., #thesis, #coding) for filtering.
AC: Multi‑select chips; filter persists for current view only.

Widgets & Shortcuts
    •    Home Screen & Lock Screen widgets: show today total and 7‑day trend.
AC: Tap launches app to Home; supports small/medium sizes.
    •    Siri / Shortcuts: “Start Deep Work” / “Stop Deep Work”.
AC: App Intents start/stop without opening UI.

Data & Sync
    •    On‑device by default: All data stored locally.
AC: App operates fully without sign‑in.
    •    iCloud sync (optional): Toggle to sync across devices.
AC: CloudKit container; conflict resolution = last‑writer‑wins for edits, duplicate resolution on create.
    •    Export: Share CSV of sessions (UTC timestamps, local offsets, tags).
AC: System share sheet provides CSV file.

Settings
    •    Daily goal: Set hours/day (e.g., 4.0h).
AC: Affects goal line, streak logic, and reminders.
    •    Nudge cadence: Choose 25/50/90 minutes or Off.
AC: Persisted in app storage; respected on new sessions.
    •    Privacy: Explicit statement; telemetry opt‑in (default Off).
AC: No data leaves device unless user enables sync or export.

Reliability & Edge cases
    •    Crash or kill during session: Session remains in progress.
AC: On next launch, in‑progress session resumes; elapsed computed from startedAt.
    •    Midnight rollover: In‑progress session spans days.
AC: Daily totals split by day boundaries for charts/streaks.
    •    Phone restart / battery drain: Same as crash; Live Activity is recreated (best‑effort) when app is opened.
    •    Multiple sessions: Prevent overlapping in‑progress sessions.
AC: Start is disabled when one is active; Stop finalizes exactly one.

⸻

4) UX Flows (high‑level)
    1.    Start/Stop: Home → Start → Lock Screen shows timer → optional nudge at 50′ → Stop → summary toast.
    2.    Review week: Home → Insights tab → bar chart with goal line → tap a bar to view that day’s sessions.
    3.    Tag filter: Insights → Tag filter chip row → filter chart & list.
    4.    Export: Settings → Export CSV → Share sheet.

Tone: Quiet, friendly, minimal. Monospaced timers, subtle haptics.

⸻

5) Information Architecture
    •    Home: Active timer, Today total, Recent Sessions list.
    •    Insights: Weekly chart, tag filter, streak indicator, goal.
    •    Settings: Goal, nudge cadence, iCloud sync, export, about/privacy.

⸻

6) Data Model (SwiftData)

@Model
final class FocusSession {
  @Attribute(.unique) var id: UUID
  var startedAt: Date
  var endedAt: Date?   // nil => in progress
  var note: String?
  var tags: [String]
}

@Model
final class Preferences {
  @Attribute(.unique) var id: String = "singleton"
  var dailyGoalHours: Double // e.g., 4.0
  var nudgeMinutes: Int?     // nil => Off
  var iCloudSyncEnabled: Bool
}

Computed fields (not persisted): duration, dayKey = startOfDay(startedAt)

Indexes: startedAt for efficient day range queries.

Migration v0→v1: add mood: Int16? later (e.g., 1–5) with default nil.

⸻

7) Platform Features & Frameworks
    •    UI: SwiftUI (iOS 17+), Charts
    •    Persistence: SwiftData (local) + optional CloudKit sync
    •    Live Activities: ActivityKit (Lock Screen/Dynamic Island timer)
    •    Notifications: UserNotifications (one‑off nudges)
    •    Shortcuts: App Intents (Start/Stop)
    •    Widgets: WidgetKit (Home/Lock Screen)
    •    Haptics: CoreHaptics (light taps on start/stop)

⸻

8) Technical Design

Timing
    •    Source of truth = startedAt & endedAt; UI timer derives from Date.now - startedAt and updates every second using TimelineView / Observable tick.

Live Activity lifecycle
    •    On Start: request Activity<FocusAttributes> with content state { start: now }.
    •    On Stop: activity.end(...) immediately.
    •    On app relaunch: check for active session, optionally recreate activity.

Notifications
    •    Request permission once at first start attempt.
    •    Schedule UNTimeIntervalNotificationTrigger(timeInterval: nudgeMinutes*60).
    •    Cancel all pending nudges on Stop.

Charts & aggregation
    •    Query sessions in last N days.
    •    Group by startOfDay(startedAt); for spanning sessions, segment across day boundaries.
    •    Sums to hours; plot with BarMark + RuleMark(goal).

iCloud sync (optional)
    •    CloudKit backed container (same schema as SwiftData models).
    •    Conflict policy: last‑writer‑wins; duplicates merged by id.

Export CSV
    •    Columns: id, started_at_iso8601, ended_at_iso8601, duration_s, tags, note.
    •    Use ISO8601DateFormatter with timezone info; escape commas/newlines in note.

Settings storage
    •    Preferences singleton stored in SwiftData; read via @Query.

Error handling
    •    Non‑fatal persistence errors: show in‑app non‑blocking banner; retry on next launch.
    •    Prevent double starts; gray out Start when active != nil.

Accessibility & i18n
    •    VoiceOver labels on Start/Stop/Timer, large content sizes supported.
    •    Localizable strings from day one; use MeasurementFormatter for hours.

⸻

9) OpenAI CLI (Codex) Dev Workflow

Goal: Pair‑program with a coding agent that proposes diffs, while Xcode builds/runs.
    •    Install: npm i -g @openai/codex → codex login.
    •    Run in repo root: codex (approval mode = ask).
    •    Prompts you’ll use:
    •    “Generate SwiftData migrations for adding mood with backfill script.”
    •    “Create unit tests for day‑boundary splitting logic.”
    •    “Refactor FocusManager into smaller files, keep API stable.”
    •    Git hygiene: keep CLI proposals in separate branches; require green build (CI fastlane lane optional later).

⸻

10) Security & Privacy
    •    Default: on‑device only. No third‑party analytics by default.
    •    Telemetry (optional): page views and feature events via app‑owned endpoint, opt‑in only; no session notes/tags.
    •    iCloud: end‑to‑end Apple infrastructure; user can disable at any time.
    •    Clear privacy page and Data Export (CSV).

⸻

11) Performance Targets
    •    Cold launch < 350ms to first render on A15+.
    •    Timer tick jitter < 50ms.
    •    Widget load budget < 200ms.
    •    Aggregation of 1‑year history < 80ms P95 on device.

⸻

12) QA Plan

Unit tests
    •    Duration math (including DST/UTC conversions)
    •    Day‑split logic across midnight
    •    Streak calculation with gaps & restarts
    •    CSV export round‑trip (parse → equals)

UI tests
    •    Start/Stop flow + Live Activity visible
    •    Permission prompts (notifications) do not block core flows
    •    Widgets show correct totals

Exploratory
    •    Kill app during session; verify persistence
    •    Change time zone mid‑week; verify charts

⸻

13) Release Plan
    •    v0.1 (Internal): Start/Stop, Live Activity, Today total, Weekly chart, Settings (goal+nudges), CSV export.
    •    v0.2: Tags, notes, streaks, widgets, Siri/Shortcuts.
    •    v1.0 (TestFlight): iCloud sync, accessibility polish, telemetry opt‑in.

App Store positioning: “A quiet, privacy‑first deep work timer with honest weekly insights.”

⸻

14) Open Questions
    •    Minimum iOS target? (iOS 17 now; stretch to 16?)
    •    Include a break timer mode (Pomodoro‑like) or keep v1 pure?
    •    Multi‑device simultaneous sessions—merge or disallow?
    •    Should Live Activity show tag/note snippets?

⸻

15) Appendix: Example Data & CSV

id,started_at_iso8601,ended_at_iso8601,duration_s,tags,note
"e8c…",2025-08-25T08:32:10+03:00,2025-08-25T10:02:15+03:00,5405,"[coding,thesis]","chapter 2 outline"


⸻

16) Engineering Tasks (Backlog, v0.1)
    •    SwiftData models + migrations scaffold
    •    FocusManager (start/stop, nudge scheduling)
    •    Live Activity attributes + widget extension
    •    HomeView timer + Recent list
    •    InsightsView with weekly Bars + goal RuleMark
    •    SettingsView (goal, nudge cadence, privacy text)
    •    CSV export utility + Share sheet
    •    Unit tests (duration, day split, streaks)
    •    App Intents (start/stop) — if time
    •    Icons & basic theming

⸻

End of spec v0.1
