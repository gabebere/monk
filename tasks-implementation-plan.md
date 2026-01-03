# tasks-implementation-plan.md

This document is written for Codex. It is intentionally pedantic: it specifies file boundaries, target boundaries, and edge cases to prevent regressions (especially SwiftData macro issues and CloudKit constraints).

---

## 0) Guiding principles (non-negotiable)

### 0.1 CloudKit + SwiftData relationships
If the store is CloudKit-backed, every relationship must be optional, including to-many:
- Never define `var tasks: [FocusTask] = []` in a CloudKit SwiftData model.
- Instead define `var tasks: [FocusTask]?` and provide computed `unwrapped` helpers for UI.

### 0.2 Extensions must not compile SwiftData
Live Activities / Widgets must not:
- import SwiftData
- compile any SwiftData @Model types
- reference Project/FocusSession/FocusTask SwiftData types directly

All extension UI must be driven by a `Codable` snapshot written by the main app into an App Group location (UserDefaults or JSON file).

### 0.3 Incremental delivery & feature flags
Implement in small, testable steps:
- Add a `FeatureFlags.swift` (or similar) with `static let tasksV1Enabled`.
- Keep the old UI path available until Tasks v1 is stable.
- Avoid deleting old code until replacement is in production.

### 0.4 Store compatibility during development
SwiftData schema changes can break store loading.
During development:
- Prefer a DEBUG-only “Reset local store” command.
- Use a clearly named store file URL so it’s easy to delete.
- Expect that you may delete app data after schema changes.

---

## 1) Branch + rollback plan (engineering workflow)

1) Identify a known-good commit SHA where Live Activities/widgets are working.
2) Create a branch from that commit:
   - `restore/live-activities`
3) Create a new working branch from that:
   - `feature/tasks-v1`
4) Bring task-related changes via cherry-pick or manual re-apply.
   - Do NOT “hard reset” the primary branch again.

Outcome: Live Activities remain intact while tasks work proceeds safely.

---

## 2) Files and targets (explicit)

### Main app target (allowed)
- SwiftData models: Project, FocusSession, FocusTask
- SwiftData container creation
- Task UI: ScheduledTasksView, TaskEditorView
- Projects tab replacement
- Calendar + analytics integration
- Snapshot writer for extensions

### Extension targets (forbidden)
- SwiftData @Model
- Any file that imports SwiftData
- Anything that queries SwiftData container

Extensions only consume:
- MonkSharedSnapshot structs (Codable)
- Snapshot reader
- ActivityKit rendering (pure UI)

---

## 3) Data model setup (SwiftData)

### 3.1 Create TaskRecurrence enum
File: `Models/TaskRecurrence.swift`

- Define enum:
  - cases: none, daily, weekly, monthly, custom
- Ensure defaults used in @Model are fully-qualified when needed (e.g., `TaskRecurrence.none`).

### 3.2 Create FocusTask @Model
File: `Models/FocusTask.swift`

Required stored properties:
- id, title, notes
- targetDate, dueDate
- isCompleted, completedAt
- recurrence, recurrenceIntervalDays
- createdAt, updatedAt

Relationships (ALL OPTIONAL):
- project: Project?
- parent: FocusTask?
- subtasks: [FocusTask]?
- sessions: [FocusSession]?

Relationship inverses:
- Put `inverse:` only on one side (prefer to specify inverse on the to-many side to reduce macro recursion).
- Ensure the property referenced by `inverse:` is also a @Relationship.

Important: arrays must be optional for CloudKit.

Computed helpers (main app only):
- `var subtasksUnwrapped: [FocusTask] { subtasks ?? [] }`
- `var sessionsUnwrapped: [FocusSession] { sessions ?? [] }`
- `var displayTitle: String` → “Parent: Child” rule.

### 3.3 Update FocusSession @Model
File: `Models/FocusSession.swift`

- Add:
  - `@Relationship(deleteRule: .nullify) var task: FocusTask?`

### 3.4 Update Project @Model
File: `Models/Project.swift`

- Add:
  - `@Relationship(deleteRule: .cascade) var tasks: [FocusTask]?`
- If there is also a relationship to FocusSession (`sessions`), keep it optional as well.

Computed helper:
- `var tasksUnwrapped: [FocusTask] { tasks ?? [] }`

### 3.5 Update schema registration
File: wherever ModelContainer schema is created (likely `MonkApp.swift`)

- Ensure schema includes `FocusTask` along with Project and FocusSession.

### 3.6 Ensure model files are NOT in extension targets
In Xcode:
- Uncheck target membership for any SwiftData model files in Widget/Live Activity extensions.

Optional guard patterns (only if you must share a file between targets):
- Use separate folders: `Models/` for main app only, `Shared/` for extensions
- Avoid conditional compilation hacks if you can just remove target membership.

---

## 4) SwiftData container + store URL (stability)

### 4.1 Use an explicit store URL
- Create a store URL in Application Support or App Group (depending on current architecture).
- Name it clearly: `Monk.store` (or `default.store` if required, but keep consistency).

### 4.2 CloudKit configuration
- When CloudKit is enabled, use CloudKit ModelConfiguration.
- Ensure iCloud container string matches your entitlements.

### 4.3 DEBUG-only reset option
Add a debug menu action that:
- deletes the store file
- relaunches / recreates container

Do NOT ship automatic deletion in production builds.

---

## 5) Home: ScheduledTasksView

### 5.1 New view files
- `Views/Tasks/ScheduledTasksView.swift`
- `Views/Tasks/ScheduledTaskRow.swift`
- `Views/Tasks/TaskSectionHeader.swift` (optional)

### 5.2 Data structure: Scheduled entry duplication
Define a lightweight view model:

ScheduledEntry {
taskID: UUID
date: Date (start of day)
kind: .target or .due
colorStyle: .white or .red
}

Generation rules:
- If task.targetDate != nil:
  - create entry(kind: target, date: startOfDay(targetDate))
- If task.dueDate != nil:
  - create entry(kind: due, date: startOfDay(dueDate))
- If both exist, you get two entries.
- If neither exists, task does not appear in ScheduledTasksView (v1 scope).

### 5.3 Sorting rules
- Sort sections by day ascending.
- Sort entries within day:
  1) due entries before target entries OR vice versa (choose one and keep consistent).
  2) then by time (if you preserve actual time; otherwise stable by title).
  3) stable tie-breaker: taskID.

### 5.4 Completed filtering
State:
- `@AppStorage("tasks.showCompleted") var showCompleted: Bool`

If showCompleted == false:
- exclude tasks where isCompleted == true
If showCompleted == true:
- include them and render with strikethrough.

Completed count indicator:
- Count completed tasks that would otherwise be in the schedule.

### 5.5 Selection model
State in Home:
- `@State var selectedTaskID: UUID?`

Selection behavior:
- Tap row background:
  - if selectedTaskID == taskID: set to nil (toggle off)
  - else set selectedTaskID = taskID
- When selectedTaskID != nil:
  - dim titles of all non-selected rows (do not disable buttons).

Button interaction rules:
- Edit button and completion button must not toggle selection.
- Completion may clear selection if the completed task is hidden by filter.

### 5.6 Completion + recurrence spawn
On completion tap:
- Toggle completion state:
  - If marking complete:
    - set isCompleted = true
    - set completedAt = now
    - apply haptic
    - if recurrence != none: create next instance
  - If un-completing:
    - set isCompleted = false
    - set completedAt = nil
    - do NOT auto-delete spawned tasks (v1 simplification)

Spawn rules:
- New task inherits:
  - title, notes, project, parent (optional; define policy)
  - recurrence fields unchanged
  - createdAt/updatedAt = now
  - isCompleted false
  - completedAt nil
- Date shifting policy:
  - If dueDate exists: shift by recurrence period
  - If targetDate exists: shift by recurrence period
  - If both exist: shift both by same recurrence period
- Recurrence period:
  - daily: +1 day
  - weekly: +7 days
  - monthly: +1 month (Calendar add)
  - custom: +intervalDays

### 5.7 Integration in HomeView
- Insert ScheduledTasksView below timer card.
- Keep existing animated background and timer card unchanged.

Home header:
- Add “New task” button → opens TaskEditorView in create mode.
- Add show/hide completed toggle.

---

## 6) TaskEditorView

### 6.1 New view files
- `Views/Tasks/TaskEditorView.swift`
- `Views/Tasks/TaskRecurrencePicker.swift` (optional)

### 6.2 Modes: create vs edit
Define:
- `enum EditorMode { case create(defaultProject: Project?), edit(task: FocusTask) }`

### 6.3 Form fields & validation
Fields:
- title (required)
- notes
- toggles for target date and due date
- if toggle on → show DatePicker
- recurrence segmented control:
  - none/daily/weekly/monthly/custom
- if custom → show numeric stepper/text field for intervalDays (>= 1)
- project picker:
  - optional
  - allow “No project”
- parent picker:
  - optional
  - exclude selecting itself
  - exclude selecting its own child tasks (avoid cycles)

Validation rules:
- Trim title whitespace; disallow empty.
- If custom recurrence selected, intervalDays must be >= 1.

Save:
- Create new FocusTask or update existing.
- Always set updatedAt = now.
- For create: createdAt = now.
- If toggles are off: set corresponding date to nil.

Dismiss:
- Use standard navigation dismiss.

---

## 7) Start session flow (Task → FocusSession)

### 7.1 Home start action uses selection
When user taps Start:
- If selectedTaskID == nil:
  - Start as today’s default behavior (no task).
- If selectedTaskID != nil:
  - Fetch selected task.
  - If task.project != nil:
    - start immediately with that project
  - else:
    - show project picker modal:
      - options: existing projects + “No project”
    - on confirm: start session

### 7.2 Persist on FocusSession
When starting:
- set FocusSession.task = selectedTask (optional)
- set FocusSession.project appropriately (whatever your current data model uses)
- ensure analytics event includes `task_id` if task present

---

## 8) Calendar integration changes

Wherever calendar events are created/updated:
- Title format:
  - task + project → `"[Task] from [Project]"`
  - task only → `"[Task]"`
  - project only → `"[Project]"`
- Remove `"[Monk]"` prefix.
- Notes must include a stable marker with sessionID to allow matching.
- Preserve location behavior.

Calendar preview card:
- Display the same title string used in calendar.

---

## 9) Replace Insights tab with Projects tab

### 9.1 Create ProjectsTabView
File: `Views/Projects/ProjectsTabView.swift`

- Reuse existing project grid/cards/detail view.
- Ensure navigation routes work (existing new-project, edit, detail).

### 9.2 Remove old Insights tab
- Update TabView to replace Insights with Projects.
- Do not delete Insights code until Projects tab is verified.
- After verification, remove Insights-related files from app target.
- For widgets/live activities: remove any dependency on Insights analyzers.

---

## 10) Live Activities / Widgets safety (snapshot approach)

### 10.1 Create shared snapshot models (NO SwiftData)
Folder: `Shared/Snapshot/`

Define `Codable` structs:
- `LiveSnapshot`
  - currentTimerState (running/paused/stopped)
  - currentSessionID
  - currentTaskTitle (String?)
  - currentProjectTitle (String?)
  - elapsedSeconds
  - lastUpdatedAt

### 10.2 App writes snapshot
In main app:
- On session start/stop/pause/update:
  - write snapshot to App Group UserDefaults or JSON file
- Use a single writer utility:
  - `SnapshotWriter.write(_:)`

### 10.3 Extensions read snapshot
In widgets/live activities:
- Read snapshot only.
- Never query SwiftData.
- Display task/project titles if present.

This isolates extensions from schema/model churn forever.

---

## 11) QA checklist (must pass before shipping)

### Build targets
- Main app builds in Debug + Release.
- Widget extension builds in Debug + Release.
- Live activity extension builds in Debug + Release.

### Functional checks
- Create task with due date only → shows once (red) on correct day.
- Create task with target date only → shows once (white) on correct day.
- Create task with both dates → shows twice in correct days.
- Selection dims others; buttons do not interfere.
- Show/Hide completed works; completed count accurate.
- Completing recurring task spawns next instance; dates shift correctly.
- Start session with selected task:
  - if project exists: no prompt
  - if project missing: prompt appears
- Calendar event titles follow new format; notes include session marker.
- Projects tab renders; Insights removed without breaking.

### SwiftData/CloudKit checks
- ModelContainer loads with CloudKit enabled.
- Ensure all relationships optional.
- If store fails after schema change during dev, reset store and retry.

---

## 12) Suggested PR breakdown (to avoid regressions)

PR A: Extension isolation + snapshot plumbing (no tasks yet)
PR B: FocusTask model + schema + container loads
PR C: ScheduledTasksView in Home (behind feature flag)
PR D: TaskEditorView + recurrence spawn
PR E: Session + calendar + analytics integration
PR F: Projects tab replaces Insights; remove Insights artifacts