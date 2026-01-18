# Interdevice Mirroring (CloudKit + KVS)

This document describes how to mirror live focus sessions across a user’s devices (same Apple ID) with minimal user prompts, using CloudKit subscription pushes to wake background/terminated apps and iCloud KVS as a fallback.

## Goals
- Auto-mirror start/stop events across iPhone/iPad (mac later) with <10s propagation.
- If idle: silently start mirrored session and activate shields; no notification.
- On stop: silently stop mirrored session and lift shields.
- Conflicts: notify only when another session is active on the receiving device.
- No custom server; CloudKit private DB + push subscription only.

## Transport & Data
- Primary: CloudKit private DB record `SessionMirrorEvent` + database subscription → silent push.
- Fallback: iCloud KVS mirror of the same payload (best-effort, optional).
- Scope: Same Apple ID only.

### SessionMirrorEvent fields
- `eventId: UUID`
- `sessionId: UUID`
- `kind: String` (`start` | `stop`)
- `timestamp: Date`
- `ttlSeconds: Int` (e.g., 300)
- `sourceDeviceId: String`
- `sourceDeviceName: String`
- `taskId: UUID?`, `taskTitle: String?`
- `projectId: UUID?`, `projectTitle: String?`
- `durationHintSeconds: Double?` (optional)
- `hash: String` (hash of key fields for dedupe)

## Emit Flow (originating device)
- On `start(project:task:)`: write `SessionMirrorEvent(kind: start)` with TTL, task/project, source device info; optionally KVS mirror.
- On `stop`: write `SessionMirrorEvent(kind: stop)` (include `durationHintSeconds` if desired).
- Respect setting “Participate in mirroring” for emitting? (recommended: still emit; setting gates consumption).

## Receive Flow (other devices)
Triggered by CloudKit push handler (`application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`), or foreground KVS poll.

1) Guard: feature toggle “This device participates in mirroring” (default ON).  
2) Dedupe/TTL: drop if `eventId/hash` seen or `timestamp + ttlSeconds` < now - skewAllowance (~30s).  
3) `kind == start`:
   - If no active session: auto-start mirrored session (`startedAt = timestamp` clamped to now if stale), attach task/project, attempt shields. No notification if succeeds.
   - If already active: latest wins — if incoming start time is newer than the current session, end the current session, deactivate shields, and replace with the incoming session. If incoming is older, ignore.
4) `kind == stop`:
   - If there is an active session newer than the stop timestamp (latest wins), ignore the stop.
   - Otherwise, stop the matching session (by id/task/project) and lift shields silently; if no match but shields active, lift shields.
   - Notify only on failure (e.g., permission).

## Notifications
- Only on failures (e.g., shield permission issues). No conflict notifications; latest session always wins.

## Shields
- On auto-mirror start: attempt `HardBlockManager.activate`; on failure log + optional prompt to enable Screen Time.
- On stop: always lift shields; no prompt if successful.
- Tie shield state to the active session on that device to avoid stranding.

## Settings
- Add toggle (Settings): “Participate in mirroring” (default ON). When OFF: ignore incoming events; consider still emitting for other devices.
- Optional debug: “View last mirror events” log for QA.

## Persistence & Dedupe
- Maintain small persisted set (UserDefaults) of processed `eventId/hash` with timestamps; evict after ~24h.
- TTL enforcement: default 5m; clamp start time if late but not expired.

## Background/terminated behavior
- CloudKit subscription push can wake the app briefly even if terminated; do work in the push handler, minimal UI.
- If background refresh/notifications disabled or push delayed, apply on next launch; TTL prevents stale mirroring.
- KVS fallback only works when the app is alive (foreground/background).

## Testing Checklist
- Start on device A, device B idle → B auto-starts + shields within ~10s, no notification.
- Start on A, B already active → B gets conflict notification; actions behave correctly.
- Stop on A, B mirrored → B auto-stops and lifts shields.
- Screen Time permission missing on B → start on A logs failure and (optionally) prompts to enable.
- App terminated on B → start on A; CK push wakes B and mirrors (validate).
- TTL drop: stale start ignored.
- Toggle off mirroring on B → start on A; B ignores event.

## Integration Steps (summary)
1) Define `SessionMirrorEvent` type + CloudKit record mapper; reuse `iCloud.com.gbr.Monk`.
2) Add emitter hooks in `FocusManager.start/stop`.
3) Register CloudKit DB subscription; persist subscription state; request remote notification entitlement (silent).
4) Implement receiver: CK push handler → fetch changed records → apply flow above; add KVS poll as optional fallback.
5) Add conflict notification with actions wired to intents/app delegate.
6) Update Settings with mirroring toggle (default ON).
7) Add logging/metrics for mirror events, TTL drops, shield failures.
