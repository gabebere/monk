# tasks-and-projects-spec.md

## Overview

We are adding a first-class Task system to Monk, integrating tasks with focus sessions and calendar logging, and reorganizing navigation:

1) **Home**: hosts a Reminders-style **Scheduled Tasks** list below the existing timer card (Home keeps its visual identity).
2) **Insights tab** is replaced with a **Projects** tab that reuses the existing project grid/cards/detail flows.
3) Introduce a **FocusTask** SwiftData model with:
   - target date + due date
   - recurrence
   - optional project association
   - optional parent/subtasks
   - integration with FocusSession and calendar titles

This spec is intentionally scoped: it aims for a clean “v1” that is stable under SwiftData+CloudKit and does not break Live Activities / Widgets.

---

## Goals

### Product goals
- Enable users to create tasks, schedule them by date (target/due), and complete them quickly from Home.
- Allow a user to start a focus session “for a task.”
- Ensure calendar logging and analytics reflect the chosen task (and project when present).

### Engineering goals
- Keep the system stable with **SwiftData + CloudKit**.
- Ensure **app extensions never compile SwiftData models**.
- Avoid “big-bang” refactors: ship in incremental, reversible steps.

---

## Non-goals (explicitly out of scope for v1)
- Smart lists, flags, priority, tags, sorting by priority.
- Multi-level subtask tree UI (only parent → child display is supported).
- Separate lists like Reminders (tasks live globally; optionally linked to a project).
- Complex recurrence (only basic daily/weekly/monthly/custom fixed interval days).
- Sharing tasks via CloudKit public sharing.

---

## Architecture Constraints (critical)

### CloudKit + SwiftData requirement
When the SwiftData store is CloudKit-backed, **all relationships must be optional**, including to-many relationships.

That means:
- `Project.tasks` must be `[FocusTask]?`
- `Project.sessions` must be `[FocusSession]?`
- `FocusTask.subtasks` must be `[FocusTask]?`
- `FocusTask.sessions` must be `[FocusSession]?`
- etc.

UI convenience must be achieved via computed “unwrapped” helpers, not by making relationships non-optional.

### Extensions must not compile SwiftData
Live Activities and Widgets must not import/compile SwiftData models. Extensions must read “snapshot” data from the app (App Group JSON/UserDefaults) and never touch SwiftData.

---

## Data Model

### FocusTask (SwiftData @Model)

Stored properties:
- `id: UUID`
- `title: String` (required; default `""` but validation forbids saving empty)
- `notes: String?`

Dates:
- `targetDate: Date?` (soft date)
- `dueDate: Date?` (hard date)

Completion:
- `isCompleted: Bool` (default false)
- `completedAt: Date?`

Recurrence:
- `recurrence: TaskRecurrence` (enum: none/daily/weekly/monthly/custom)
- `recurrenceIntervalDays: Int?` (only used when recurrence is custom)

Metadata:
- `createdAt: Date`
- `updatedAt: Date`

Relationships (ALL OPTIONAL for CloudKit):
- `project: Project?` (inverse: `Project.tasks`)
- `parent: FocusTask?` (for subtasks)
- `subtasks: [FocusTask]?` (inverse: `FocusTask.parent`)
- `sessions: [FocusSession]?` (inverse: `FocusSession.task`)

Display rules:
- If `parent != nil`: display title as `"ParentTitle: ChildTitle"`.
- If `project == nil`: project label can be omitted entirely (“No project” is not shown).

### FocusSession (SwiftData @Model)
Add:
- `task: FocusTask?` relationship

### Project (SwiftData @Model)
Add:
- `tasks: [FocusTask]?` relationship

---

## Home Screen: Scheduled Tasks View

### Layout
- Home continues to show:
  - animated background
  - existing timer card
- Below the timer card, show `ScheduledTasksView`.

### List grouping
- Tasks are grouped by day sections.
- Days with no tasks are hidden.
- Each FocusTask may appear **0–2 times**:
  - once for `targetDate` entry (white styling)
  - once for `dueDate` entry (red styling)
- If a task has both target+due, it appears twice (two separate rows in two date buckets, possibly same day).

### Row content
Each row shows:
- Title (with parent prefix if applicable)
- Optional project name label (if set)
- Optional recurrence label (if recurrence != none)

Row controls:
- Leading “…” edit button → opens TaskEditor
- Trailing completion circle → completes/uncompletes task

Selection behavior:
- Default: nothing selected.
- Tap row background → select that row’s underlying task (selection is per task id).
- When a task is selected, other rows dim their title (not hidden).
- Tapping completion/edit buttons must not conflict with selection.

Completed handling:
- Global toggle: “Show completed” / “Hide completed”
- If hidden: completed tasks are filtered out.
- If shown: completed tasks are shown with strikethrough.
- Completed count indicator (e.g., “3 completed”).

Completion UX:
- Haptic feedback on completion.
- If show-completed is OFF, and a selected task becomes completed, selection may clear to avoid “invisible selection”.

Recurrence completion behavior:
- If task is completed and recurrence != none:
  - automatically create the next task instance (see recurrence rules)
  - mark current task complete
  - next instance inherits relevant fields (title, notes, project, parent rules, due/target shift policy)

---

## Task Editor

Fields:
- Title (required)
- Notes (optional)
- Target date (toggle + date picker)
- Due date (toggle + date picker)
- Recurrence picker:
  - segmented: None / Daily / Weekly / Monthly / Custom
  - if Custom: interval (days) input
- Project picker (optional)
- Parent task picker (optional)

Save behavior:
- Create new task or update existing
- Update `updatedAt` on save
- Validation:
  - title must not be empty/whitespace
  - if custom recurrence chosen: interval must be >= 1
  - if both dates exist: allow any ordering (do not enforce target <= due in v1)

Defaults:
- When editing an existing task:
  - default project selection = existing
- When creating a task:
  - optional “defaultProject” may be passed by caller (e.g., from selected task’s project)

---

## Session + Calendar Integration

Starting a focus session with a selected task:
- If selected task has a project: start immediately.
- If selected task has no project: prompt user to pick a project or “No project”, then start.
- Save `FocusSession.task = selectedTask`.

Analytics:
- Include `task_id` in start/stop tracking.

Calendar events:
- Event title format:
  - both task and project: `"[Task] from [Project]"`
  - only task: `"[Task]"`
  - only project (if session started via project without task): `"[Project]"`
- Remove any previous `"[Monk]"` prefix.
- Event notes must include a stable session-id marker for later reconciliation.
- Location updates remain unchanged.
- Calendar preview card shows task+project title string.

---

## Projects Tab (replaces Insights)

- Replace Insights tab with Projects tab.
- Projects tab uses existing project grid/cards.
- Existing project detail + new project flows remain.
- Remove old Insights logic from app target after Projects tab is working.

---

## Extension / Live Activity Data

Widgets/Live Activities must not depend on SwiftData models.
The app must publish a lightweight `Codable` snapshot (App Group) for:
- current focus session state
- current task title (if any)
- current project title (if any)

Extensions display using snapshot only.