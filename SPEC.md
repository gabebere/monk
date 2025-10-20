  Deep Work Tracker — Product & Technical Spec (v0.1)

iOS app that tracks “Deep Work” hours akin to Apple Watch Sleep: simple start/stop, rich weekly insights, and privacy-first on‑device data. Includes a smooth dev workflow using the OpenAI CLI (Codex) alongside Xcode.

⸻

1) Product Overview

Problem: Knowledge workers struggle to protect deep-focus time and to see honest trends (hours/day, streaks). On top of that, the current solution for apps is to block the most distracting apps, not all of them, when in reality, apps that might be seem as productive at a specific moment might be the distraction in another.

Solution: A SwiftUI iOS app with one‑tap Start/Stop, an in‑app timer with rich weekly insights, realistic goals, and automatic iCloud sync.

Success metrics (v1)
    •    D1 activation: ≥60% complete ≥1 session after install
    •    Median daily deep‑work time (active users): ≥2.5 h
    •    Day‑7 retention: ≥30%
    •    Weekly goal attainment rate: ≥40% of active users hit their weekly goal

Non‑goals (v1)
    •    Automatic detection from device usage (Screen Time)
    •    Cross‑platform (macOS, watchOS, Android)
    •    Team/manager dashboards

⸻

2) Personas & Jobs‑to‑be‑Done (JTBD)
    1.    Student: “When I sit to study, I want a clean timer and weekly proof I’m consistent, so I can feel progress and pass exams.”
    2.    Engineer/Founder: “When I time block mornings, I want frictionless Start/Stop and a minimal timer so I avoid context switching.”
    3.    Researcher/Writer: “When planning a draft week, I want goal lines and streaks so I stay accountable without sharing my data.”

⸻

3) User Stories & Acceptance Criteria

Core timing
    •    Start a session: As a user I can tap Start to begin logging; a timer appears in‑app.
AC: Start inserts a FocusSession with startedAt=now, endedAt=nil.
    •    Stop a session: Tap Stop to finalize.
AC: Session saved with endedAt=now.

Insights
    •    Today total: See today’s accumulated deep‑work time.
AC: Sum of durations where startOfDay(startedAt) == today.
    •    Weekly chart: View a bar chart of the last 7–14 days in hours.
AC: Each bar = total daily hours; includes optional goal RuleMark.
    •    Streaks: Show consecutive weeks hitting a weekly goal.
AC: Consecutive week count increments when the last 7-day sum ≥ weekly goal.

Organization
    •    Session mood: Quick slider between Bad / Neutral / Good.
AC: Saved as part of each session and editable later.
    •    Projects: Create projects with unique visual identity, assign sessions, and configure per-project hard blocking.
AC: User selects a project (or “none”) on session start; hours roll up per project; project hard block overrides global soft block during the session.
    •    Live Activity (iPhone): While a focus session is running, show an ActivityKit view with elapsed time and title on the Lock Screen/Dynamic Island.
AC: Requires enabling the MonkLiveActivities WidgetKit extension.

Optional extensions (deferred)
    •    Shortcuts automation via App Intents.
AC: Define start/stop intents that operate without opening the UI.

Data & Sync
    •    SwiftData + CloudKit: Focus sessions, projects, and preferences sync via private CloudKit container `iCloud.com.gbr.Monk`.
AC: Schema provisions in CloudKit; last-writer-wins merges; new devices see existing data after login.

Settings
    •    Weekly goal: Set hours/week (e.g., 40h).
AC: Drives goal line, streak logic, and reminders.
    •    Privacy: Explicit statement; telemetry opt-in (default Off).
AC: No data leaves device without explicit opt-in.
    •    Soft blocking: Choose apps to shield during focus periods.
AC: Toggle to enable; user picks apps via FamilyActivityPicker.

Reliability & Edge cases
    •    Crash or kill during session: Session remains in progress.
AC: On next launch, in‑progress session resumes; elapsed computed from startedAt.
    •    Midnight rollover: In‑progress session spans days.
AC: Daily totals split by day boundaries for charts/streaks.
    •    Multiple sessions: Prevent overlapping in‑progress sessions.
AC: Start is disabled when one is active; Stop finalizes exactly one.

⸻

4) UX Flows (high‑level)
    1.    Start/Stop: Home → Start → in-app timer runs → Stop → summary toast.
    2.    Review week: Home → Insights tab → bar chart with goal line → tap a bar to view that day’s sessions.
Tone: Quiet, friendly, minimal. Monospaced timers, subtle haptics.

⸻

5) Information Architecture
    •    Home: Active timer, Today total, Recent Sessions list.
    •    Insights: Weekly/daily charts, focus timeline, streak indicator, goal.
    •    Settings: Weekly goal, discard-short toggle, about/privacy.

⸻

6) Data Model (SwiftData)

@Model
final class FocusSession {
  @Attribute(.unique) var id: UUID
  var startedAt: Date
  var endedAt: Date?   // nil => in progress
  var moodScore: Int?
  var project: Project?
}

@Model
final class Preferences {
  @Attribute(.unique) var id: String = "singleton"
  var weeklyGoalHours: Double // e.g., 40.0
  var discardShortSessions: Bool?
  var softBlockEnabled: Bool
  var softBlockSelectionData: Data?
}

@Model
final class Project {
  @Attribute(.unique) var id: UUID
  var title: String
  var createdAt: Date
  var gradientIndex: Int
  var softBlockEnabled: Bool
  var softBlockSelectionData: Data?
  var hardBlockEnabled: Bool
  var hardBlockSelectionData: Data?
  @Relationship(deleteRule: .nullify, inverse: \FocusSession.project) var sessions: [FocusSession]
}

Computed fields (not persisted): duration, dayKey = startOfDay(startedAt)

Indexes: startedAt for efficient day range queries.

Migration v0→v1: add mood: Int16? later (e.g., 1–5) with default nil.

⸻

7) Platform Features & Frameworks
    •    UI: SwiftUI (iOS 17+), Charts
    •    Persistence: SwiftData (local) + optional CloudKit sync
    •    Haptics: CoreHaptics / UIFeedbackGenerator (taps on start/stop)

⸻

8) Technical Design

Timing
    •    Source of truth = startedAt & endedAt; UI timer derives from Date.now - startedAt and updates every second using TimelineView / Observable tick.

Charts & aggregation
    •    Query sessions in last N days.
    •    Group by startOfDay(startedAt); for spanning sessions, segment across day boundaries.
    •    Sums to hours; plot with BarMark + RuleMark(goal).

iCloud sync
    •    CloudKit backed container (same schema as SwiftData models).
    •    Conflict policy: last‑writer‑wins; duplicates merged by id.

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
    •    Telemetry (optional): page views and feature events via app-owned endpoint, opt-in only; no session notes stored remotely.
    •    iCloud: end‑to‑end Apple infrastructure; always enabled when available.
    •    Clear privacy page outlining data handling.

⸻

11) Performance Targets
    •    Cold launch < 350ms to first render on A15+.
    •    Timer tick jitter < 50ms.
    •    Aggregation of 1‑year history < 80ms P95 on device.

⸻

12) QA Plan

Unit tests
    •    Duration math (including DST/UTC conversions)
    •    Day‑split logic across midnight
    •    Streak calculation with gaps & restarts

UI tests
    •    Start/Stop flow updates timer and Today total
    •    Permission prompts (notifications) do not block core flows

Exploratory
    •    Kill app during session; verify persistence
    •    Change time zone mid‑week; verify charts

⸻

13) Release Plan
    •    v0.1 (Internal): Start/Stop, Today total, Weekly chart, Settings (weekly goal), history list.
    •    v0.2: Notes, streaks, Siri/Shortcuts (if prioritized).
    •    v1.0 (TestFlight): iCloud sync, accessibility polish, telemetry opt‑in.

App Store positioning: “A quiet, privacy‑first deep work timer with honest weekly insights.”

⸻

14) Open Questions
    •    Minimum iOS target? (iOS 17 now; stretch to 16?)
    •    Include a break timer mode (Pomodoro‑like) or keep v1 pure?
    •    Multi‑device simultaneous sessions—merge or disallow?

⸻

15) Appendix: Example Data

id,started_at_iso8601,ended_at_iso8601,duration_s,project_id
"e8c…",2025-08-25T08:32:10+03:00,2025-08-25T10:02:15+03:00,5405,"[coding,thesis]","chapter 2 outline"


⸻

16) Engineering Tasks (Backlog, v0.1)
    •    SwiftData models + migrations scaffold
    •    FocusManager (start/stop, weekly totals)
    •    HomeView timer + Recent list
    •    InsightsView with weekly Bars + goal RuleMark
    •    SettingsView (weekly goal picker, privacy text)
    •    Unit tests (duration, day split, streaks)
    •    App Intents (start/stop) — optional future work
    •    Icons & basic theming

⸻

End of spec v0.1
