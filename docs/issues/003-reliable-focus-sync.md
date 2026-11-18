# 003 — Durable and coherent cross-device focus sync

Priority: P1. Status: code remediation implemented in the 1.0 candidate; real CloudKit fault and account-change tests remain open.

## Problem and evidence

The original mobile `publish`, `publishEndedSession`, and `publishDefaultAccessConfiguration` and Mac `publish`, `end`, and `publishDefaultAccess` made one CloudKit write attempt. Failures were logged or shown as a status; no durable pending-write queue survived app termination. The Mac marked a fingerprint as delivered before its write succeeded. Its `recordForUpdate` treated any fetch failure as a missing record. Both platform apply paths rejected a different session while a local session existed, without reconciling competing sessions. Mac restoration could republish an old policy before considering newer cloud state.

The original end-record paths reused a global current-focus record and did not condition an end on the latest session generation/end date. Services lacked a complete account-bound replay policy.

## Concrete failure scenarios

- Start or finish offline, terminate the app, reconnect: the peer never receives the change.
- Two offline devices start different sessions; each retains its own policy after reconnecting.
- One device extends a session while another delayed end write is in flight; an unconditional end can overwrite the extension.
- A Mac relaunch republishes stale saved state over a newer cloud commitment.
- A pending write created under account A could be replayed after switching to account B without account binding.

## Required behavior

Persist pending portable writes before attempting delivery; serialize replay and use bounded retry/backoff for transient failures. Distinguish record absence from authorization/network errors. Handle `serverRecordChanged` by re-reading and applying a deterministic policy, never by unconditional overwrite. Pending entries must be bound to the current iCloud account, and account uncertainty/change must suspend or quarantine replay rather than move data across accounts.

Conflict rules must be shared and pure enough to test. A stale end must not terminate an extended or different active commitment. A restored local session must not silently supersede newer cloud state. Competing sessions need a deterministic convergence rule that preserves the no-early-end promise. Durable sync does not guarantee prompt iOS background execution; foreground refresh and retry remain required.

## Compatibility and migration

Continue to decode legacy focus/default records with missing optional metadata. Introduce additive fields and versioned local queue storage. Do not migrate by deleting the user's CloudKit database or disabling enforcement. Mixed-version clients must be tested; old clients that cannot honor new conflict metadata are a release compatibility risk, not something a schema field alone solves.

## Candidate remediation

`Shared/FocusSyncState.swift` centralizes portable payloads, journal coalescing, and conflict decisions. `Shared/CloudKitSyncOutbox.swift` writes the portable journal atomically in Application Support, verifies account identity, serializes conditional CloudKit saves, retries fresh change tags up to three times per server conflict, and uses exponential retry capped at 300 seconds while honoring CloudKit retry hints. Services flush during lifecycle/poll opportunities and do not blindly republish a restored policy.

Overlapping independent sessions converge on the longer deadline, with deterministic UUID tie breaking; the entire winning policy is used without unioning allowlists. Same-session later deadlines outrank earlier end markers. Account-change generations invalidate in-flight operations and quarantine the verified-owner journal until identity is rechecked. Same-account transient sign-out can resume pending writes; a different verified account drops them. Durable session/account ownership covers received/adopted sessions as well as local mutations. Mac policy persistence retains portable requests even when an app is mobile-only, so restart/extension does not erase them. This provides explicit recovery semantics, not an instantaneous distributed lock or backward compatibility with old writers that ignore these rules.

## Acceptance evidence

Unit tests: transient failure state, queue replacement/replay, stale end after extension, session conflicts in both orders, restored state, no shortening of an active local deadline, and account mismatch. Integration: airplane mode start/extend/end followed by force quit and reconnect; simultaneous starts on phone/Mac/tablet; server conflict; sign-out/sign-in with a separate test account. Record actual commit, OS, app build, environment, results, and limitation. Never attach private record contents to public issues.
