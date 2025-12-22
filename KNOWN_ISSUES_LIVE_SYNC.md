# Monk – Live Session Sync (Known Issues & Current State)

Context: Cross-device focus session propagation (iPhone → iPad) via iCloud KVS, plus local notification prompt to mirror the session and apply Screen Time blocking. No backend/push path is active.

## Current implementation
- `LiveSessionSyncService` (iOS only):
  - Publishes start/stop to `NSUbiquitousKeyValueStore` with `sessionId`, `startedAt`, `projectId`, `selectionData`, `updatedAt`, `isActive`.
  - On receiving a fresh update (staleness < 180s):
    - Looks up the project locally; applies hard block via `HardBlockManager`.
    - Mirrors the session locally (creates a `FocusSession` with the same UUID/start time) unless another in-progress session is running.
    - Schedules a local notification: “Mirror your focus session. Tap to mirror your current session to this device and apply blocking.” (uses unique identifiers; logs auth status and scheduling result).
  - Logging added: init, main-actor updates, staleness values, project fetch success/failure, mirrored session insert, notification scheduling.
- `FocusManager` sends start/stop events to the sync service.
- AppDelegate no longer routes silent pushes; KVS is the only sync path.
- Location usage strings and hard-block entitlements are present across app and extensions; `remote-notification` background mode is on.
- Projects grid, paywall, onboarding, etc., are unaffected.

## Known problems (to fix)
1) Focus session stopwatch does not sync across devices:
   - Shielding is applied, but mirrored `FocusSession` sometimes not created or not visible in UI on receiving device (timer not running).
   - Needs reliable session creation on receiver and timer/UI refresh.

2) Notification not always delivered/shown on receiving device:
   - Prompt may not appear even though shielding is active.
   - Need a robust “mirror session” alert when a remote session starts (even if app is foreground/background).

## Suggested next steps for an agent
- Verify notification permission on receiver; add an in-app banner fallback if notification is suppressed in foreground.
- Ensure `LiveSessionSyncService` is constructed on receiver and runs on main actor for SwiftData operations; consider a `ModelActor` wrapper to avoid off-main warnings.
- Tighten mirrored session creation:
  - If project lookup fails (not yet synced), store pending payload; retry when projects sync or show a banner requesting to open Monk to sync projects.
  - Force a UI refresh/hard reload of queries after inserting mirrored session.
- Improve prompt strategy:
  - Add a direct in-app toast when receiving a start while foregrounded.
  - Keep the local notification for background/terminated state; ensure unique IDs and minimal delay.
- Optional fallback: add a small BGAppRefresh task to poll KVS periodically to catch missed updates (best-effort).

## Out of scope (removed)
- Backend + silent push path was rolled back. Only KVS is active. If backend/push is desired later, see `MACOS_PLAN.md` and prior conversation for the server-backed design.

