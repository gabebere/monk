# Monk 2.0 Working Doc

Last updated: 2026-04-09
Owner: Product + Engineering
Status: Draft (baseline from current code)

## 1) Why this doc exists

Monk currently contains overlapping product directions (legacy task authoring + reminders-first flows + guided tutorial assumptions + older tab information architecture).  
This document captures the real current behavior from code so we can define a clean Monk 2.0 direction.

## 2) Current behavior (from code, not old specs)

### App navigation
- Tabs in app shell are still:
  - Home
  - Insights
  - History
  - Settings
- `ProjectsTabView` exists but is not currently wired as a tab.

### Home behavior
- Home now acts as a split workspace between:
  - `Projects`
  - `To-do's`
- Section switching:
  - tap section title
  - horizontal swipe gesture
- Starting focus:
  - tap project => start focus session immediately
  - tap to-do => start focus session (asks for project first if missing, then asks tools selection on first run)
- While a session is active, Home shows stop timer card.
- There is no standalone "Time to focus" idle CTA anymore.

### To-do’s behavior
- To-do’s list is read from `FocusTask` records that are:
  - scheduled (`dueDate != nil`)
  - reminder-backed (`reminderExternalIdentifier` or `reminderCalendarItemIdentifier` set)
- List is currently "next N" style (`maxVisibleEntries = 6`), sorted by due date then title.
- Completing a to-do updates local task and syncs completion state back to Apple Reminders.
- Empty states:
  - reminders disabled => "Apple Reminders is off."
  - reminders enabled + no tasks => "You're all caught up! ;)"

### Apple Reminders integration
- Reminders can be enabled in Settings.
- Sync shape is two-way for scheduled reminders/tasks.
- Excluded reminder lists are supported.
- Groceries-like lists are auto-seeded into exclusions once.
- Destination list setting exists for exporting legacy Monk tasks.
- Reminder metadata URL format for Monk-owned reminders:
  - `monk://task/<task-id>?parent=<parent-id>`
- External reminders without Monk metadata remain flat unless IDs match existing Monk tasks.

### Task model and editing
- `FocusTask` still exists and includes:
  - title, notes, dueDate, recurrence
  - optional project and optional parent/subtasks
  - reminder linkage IDs
  - task-specific tools selection (`focusToolsSelectionData`)
- `TaskEditorView` exists and can create/edit/delete tasks, including parent assignment and reminder upsert/delete.
- Task editor routes are currently not wired from Home.

### Focus blocking behavior
- Session blocking priority:
  1. task-specific focus tools selection
  2. project hard block selection
  3. no shield
- This makes task taps effectively task-scoped session starts with per-task blocking.

### Guided tutorial assumptions
- Tutorial still references "create project", "open to-do's", and "start with a to-do".
- Tutorial flow still tracks created task IDs and task row anchors.
- Tutorial does not fully reflect a pure reminders-source-of-truth product model yet.

## 3) Current friction map (what is fighting what)

### Product direction conflicts
- Reminders-first behavior is partially implemented, but legacy Monk task model/editor still exists as a first-class writable domain.
- "Projects replacing Insights" was planned, but app still has an Insights tab in the main shell.
- Settings copy still references "legacy Monk task export", which conflicts with a clean reminders-first mental model.

### UX consistency issues
- Home carries substantial layout logic for portrait + iPad split, plus section switching + tutorial anchors, making changes brittle.
- Projects controls live in different arrangements between Home portrait and Home split landscape.
- To-do list is intentionally minimal, but task/project mapping and reassignment flows are not yet fully explicit in-row.

### Technical shape issues
- `TaskEditorView` appears partly orphaned from active UX, but still mutates live data + reminders.
- Multiple docs/spec files describe states that no longer match runtime behavior.
- Large uncommitted diff footprint across Home/tasks/settings creates integration risk for further redesign without a product reset doc.

## 4) What we should decide for Monk 2.0

1. Source of truth for tasks:
   - Apple Reminders only
   - Monk tasks only
   - hybrid
2. Role of `FocusTask`:
   - full authoring model
   - local mirror/cache only
3. Information architecture:
   - keep Insights tab
   - replace with Projects tab
   - move projects fully into Home and reduce tabs
4. Task-to-project mapping model:
   - local mapping by reminder identifier
   - list-level defaults
   - both
5. Focus start model:
   - tap project and tap to-do both start focus (current)
   - add confirmation step
   - add separate "prepare" step
6. Blocking setup:
   - first-run per task only (current)
   - project default with optional per-task override
7. Scope for Monk 2.0 initial release:
   - strictly UX/flow cleanup
   - include model cleanup and dead path removal

## 5) Proposed execution format for this doc

When we align on your vision, we should add:
- Product principles (3-5 bullets)
- Canonical user flows
- Information architecture (tabs/screens)
- Data ownership rules (Reminders vs Monk)
- Out-of-scope list
- Migration and rollout plan
- Implementation phases with explicit file ownership

## 6) Next step

Add your Monk 2.0 vision directly under a new section:
- `## 7) Vision (Gabriel Draft)`

Then we will turn this into:
- `Monk 2.0 Product Spec`
- `Monk 2.0 Technical Plan`
- `Monk 2.0 Migration Checklist`

## 7) Vision (Gabriel Draft)

### Idea 1 (accepted): Reminders lists are the project interface

- Monk should remove legacy task/reminder creation flows inside Monk.
- Monk should behave as a focus app that interfaces tightly with Apple Reminders.
- Project mapping should not rely on tags.
- Each non-archived project should have exactly one matching Apple Reminders list.
- If a project is archived or deleted, its linked Reminders list should be deleted.
- Deleting the linked list also deletes reminders in that list.

Design intent:
- Project identity comes from list membership.
- To-do feed should no longer feel like an arbitrary blend of scheduled reminders.
- The Reminders list itself becomes the durable project container.

### Idea 2 (accepted): quick "unlock for now" intent flow

- Add a `+` control at the bottom of To-do’s for a fast unlock intent.
- This is not a task creator.
- User must enter:
  - what they will do now (free text, can include distractions like games)
  - what they want to unlock now (selected target scope)
- Add toggle: `Is this work?`
  - on => counts toward productive focus context
  - off => counts as intentional distraction context
- Add unlock timer:
  - default = 1 minute
  - user can adjust before starting unlock
- Product intent remains strict-default blocking, then explicit temporary allows through this flow.

Implementation notes:
- Store each unlock as a local event with:
  - reason text
  - unlock target(s)
  - `isWork` classification
  - duration + timestamps
- Use this unlock event history for Insights and behavior tuning (e.g., nudges, patterns).

### Idea 3 (accepted): Home-first navigation, no bottom tab bar

- Remove Insights as a primary destination.
- Remove bottom tab/page selector entirely.
- Make Home the single primary hub.
- Add a top-right `...` button on Home.
- Overflow menu includes:
  - Settings (gear)
  - History
- Settings and History should open as closeable pages from Home, not as persistent tabs.

Design intent:
- Reduce navigation overhead.
- Keep focus loops in one place.
- Move secondary surfaces behind explicit intent (`...`).

### Idea 4 (accepted): dedicated full-screen Focus mode with "Slide to End"

- When a focus session starts, Monk should switch to a dedicated Focus screen.
- Focus screen content should be intentionally minimal:
  - primary message: `Enjoy your focus on [TASK NAME]`
  - bottom control: iOS-6 style slider interaction to end the focus session
- Remove ordinary stop-button affordances in focus mode in favor of the slider gesture.

Design intent:
- Raise commitment and reduce accidental session stops.
- Make focus mode visually distinct from planning/navigation mode.
- Keep the stop action deliberate and tactile.

Platform constraint:
- Monk can implement an in-app "slide to end focus" control.
- Monk cannot literally unlock the iPhone lock screen or bypass iOS system unlock behavior.

## 8) Monk 2.0 Implementation To-do (agent-executable)

Execution order below is intentional. An agent should complete items top-to-bottom, validating build/tests after each item.

### [ ] 1. Lock product direction behind feature flags
- Goal: safely ship Monk 2.0 behavior incrementally without breaking current users.
- Implement:
  - Add `FeatureFlags.monk2Enabled` and sub-flags for `homeSingleHub`, `remindersProjectLists`, `quickUnlock`, `focusFullscreen`.
  - Gate new flows in Home/Content shell with these flags.
- Primary files:
  - `Monk/Services/FeatureFlags.swift` (or equivalent feature-flag location)
  - `Monk/ContentView.swift`
  - `Monk/Views/HomeView.swift`
- Done when:
  - App behavior can switch between old/new navigation with one flag.

### [ ] 2. Enforce project ↔ reminders-list 1:1 lifecycle
- Goal: each active project owns one Reminders list; archiving/deleting project deletes its list.
- Implement:
  - Add project field for linked list identifier (`Project.remindersListIdentifier`).
  - On project create: create list in EventKit and persist identifier.
  - On project rename: rename linked list.
  - On archive/delete: delete linked list (and therefore reminders in it) and clear local linkage.
  - If list is missing externally, recreate and relink automatically.
- Primary files:
  - `Monk/Models/Project.swift`
  - `Monk/Services/RemindersSyncService.swift`
  - `Monk/Views/Projects/ProjectDetailView.swift` (or archive/delete entry points)
  - `Monk/Views/Projects/NewProjectView.swift`
- Done when:
  - Creating, renaming, archiving, deleting a project mirrors correctly in Apple Reminders.

### [ ] 3. Move task mapping to list membership, not tags
- Goal: task project mapping comes from the reminder's calendar/list.
- Implement:
  - During reminder import, map reminder calendar identifier to project via `Project.remindersListIdentifier`.
  - Set `FocusTask.project` automatically from that mapping.
  - Stop using tags/list names as mapping logic.
- Primary files:
  - `Monk/Services/RemindersSyncService.swift`
  - `Monk/Models/FocusTask.swift`
- Done when:
  - Imported reminders in project lists always appear tied to the correct project.

### [ ] 4. Complete reminders-first data ownership
- Goal: users no longer author tasks in Monk; Monk mirrors scheduled reminders for focus.
- Implement:
  - Remove/disable all "create task" entry points and task-editor routes from UI.
  - Keep `FocusTask` as local mirror/cache for sync and focus metadata.
  - Keep import scope to scheduled reminders only.
- Primary files:
  - `Monk/Views/HomeView.swift`
  - `Monk/Views/Tasks/TaskEditorView.swift` (deprecate from navigation)
  - `Monk/Views/SettingsView.swift` (remove legacy copy/actions)
- Done when:
  - No visible path in app creates tasks directly in Monk.

### [ ] 5. One-time migration of existing Monk-only scheduled tasks
- Goal: preserve user scheduled tasks when moving to reminders-first mode.
- Implement:
  - On first Monk 2.0 launch, export local scheduled non-reminder-backed tasks into Reminders.
  - Mark migration complete with durable version key.
  - Add retry-safe idempotency (no duplicate reminders).
- Primary files:
  - `Monk/Services/RemindersSyncService.swift`
  - `Monk/Services/MirrorSyncService.swift` (if currently used for migration orchestration)
  - `Monk/ContentView.swift` or app bootstrap service
- Done when:
  - Migration runs once, is resumable, and duplicates are not produced.

### [ ] 6. Finalize Home as single hub (remove bottom tab bar)
- Goal: Home is the only primary screen.
- Implement:
  - Remove tab/page selector container from shell.
  - Add top-right `...` menu in Home.
  - Present Settings and History as closeable pages/sheets from that menu.
- Primary files:
  - `Monk/ContentView.swift`
  - `Monk/Views/HomeView.swift`
  - `Monk/Views/SettingsView.swift`
  - `Monk/Views/HistoryView.swift`
- Done when:
  - No persistent bottom tabs; Home owns navigation to secondary views.

### [ ] 7. Finalize Home Projects/To-do layout behavior
- Goal: lists use full available space with no gradient fade masking.
- Implement:
  - Keep `Projects | To-do's` selector centered for both sections.
  - Maintain full-width/full-height list containers in portrait and split layouts.
  - Remove top/bottom fade masks from both lists.
  - Keep weekly project pie chart at top of projects content and scrolling with list.
- Primary files:
  - `Monk/Views/HomeView.swift`
  - `Monk/Views/Projects/ProjectGridListView.swift`
  - `Monk/Views/Tasks/ScheduledTasksView.swift`
- Done when:
  - Scrolling content uses available area cleanly with no top/bottom fades.

### [ ] 8. Build quick "unlock for now" intent flow (+ in To-do's)
- Goal: allow temporary intentional unlock with explicit reason and duration.
- Implement:
  - Add `+` action in To-do's area that opens a quick sheet.
  - Required inputs:
    - reason text (`What will you do?`)
    - target apps/tools to unlock
    - `Is this work?` toggle
    - timer (default 1 minute)
  - On confirm: create temporary allow policy, start countdown, auto-relock at expiry.
  - Persist event locally for history/analytics.
- Primary files:
  - `Monk/Views/HomeView.swift`
  - `Monk/Services/HardBlockManager.swift`
  - `Monk/Models/` (new `UnlockIntentEvent` model)
  - `Monk/Views/` (new quick unlock sheet view)
- Done when:
  - User can unlock selected targets for exactly chosen duration, then device policy returns to blocked state.

### [ ] 9. Add dedicated full-screen Focus mode with "Slide to End"
- Goal: focus sessions run in a distinct minimal screen with deliberate stop gesture.
- Implement:
  - Present full-screen focus view whenever session is active.
  - Main text: `Enjoy your focus on [task/project name]`.
  - Replace normal stop button with custom slider control (`Slide to End`).
  - Only end session when slider completes.
- Primary files:
  - `Monk/Views/HomeView.swift`
  - `Monk/Views/` (new `FocusSessionView.swift` + slider component)
  - `Monk/Services/FocusManager.swift`
- Done when:
  - Active sessions always enter full-screen mode and require slider completion to stop.

### [ ] 10. Keep "tap starts focus" flows coherent
- Goal: project taps and to-do taps both start focus smoothly with minimal friction.
- Implement:
  - Tapping project starts session immediately.
  - Tapping to-do starts session; if project is missing, require one-time project selection.
  - Ask tool selection on first start for that task/project context and persist.
  - Reuse persisted choices on subsequent starts.
- Primary files:
  - `Monk/Views/HomeView.swift`
  - `Monk/Services/FocusManager.swift`
  - `Monk/Models/FocusTask.swift`
- Done when:
  - No dead-end taps; all start flows converge into one consistent session start path.

### [ ] 11. Remove or repurpose Insights surface
- Goal: avoid dead/unused primary surfaces while keeping useful analytics.
- Implement:
  - Remove Insights from primary navigation.
  - Keep lightweight weekly distribution summary in Projects (pie chart).
  - Route deeper analytics (if kept) behind `...` menu or History.
- Primary files:
  - `Monk/ContentView.swift`
  - `Monk/Views/InsightsView.swift`
  - `Monk/Views/Projects/ProjectGridListView.swift`
- Done when:
  - No standalone Insights tab remains in primary app shell.

### [ ] 12. QA + regression harness for Monk 2.0
- Goal: prevent sync/navigation regressions while iterating fast.
- Implement:
  - Add XCTest coverage for:
    - project/list lifecycle sync
    - scheduled reminder import filtering
    - migration idempotency
    - quick unlock timer expiry/relock
  - Add UI tests for:
    - Home-only navigation
    - `Projects | To-do's` switching + swipe
    - full-screen focus slider end flow
- Primary files:
  - `MonkTests/`
  - `MonkUITests/`
- Done when:
  - `xcodebuild test -project Monk.xcodeproj -scheme Monk -destination 'platform=iOS Simulator,name=iPhone 15'` passes with new cases.

## 9) Definition of done for Monk 2.0

- Tasks are reminders-first and sourced from Apple Reminders scheduled items.
- Every active project has a managed reminder list; archive/delete removes that list.
- Home is the primary hub with no bottom tab bar.
- Focus starts directly from projects/to-do’s and runs in full-screen focus mode.
- Temporary unlock intent flow exists with reason + `Is this work?` + 1-minute default timer.
- Build passes and automated tests cover critical sync/focus/navigation flows.
