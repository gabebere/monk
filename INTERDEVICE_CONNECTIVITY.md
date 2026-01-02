# Interdevice Connectivity (iPhone ↔ iPad)

This document describes how Monk syncs across devices today. There is no backend service; all sync uses Apple services (CloudKit + iCloud KVS).

## Summary
- **Persistent data sync** (sessions, projects, preferences): SwiftData + CloudKit private database.
- **Live session mirroring** (start/stop + Screen Time shielding): iCloud KVS (`NSUbiquitousKeyValueStore`) via `LiveSessionSyncService`.
- **Entitlement sync** (RevenueCat unlock flag): iCloud KVS via `EntitlementSyncService`.
- **No** push server, **no** local network, **no** Bluetooth/Wi‑Fi P2P.

## Persistent Data Sync (SwiftData + CloudKit)
- **Where it’s configured:** `Monk/MonkApp.swift` (and `MonkMac/MonkMacApp.swift` when mac is active).
- **How:** `ModelContainer` uses `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.gbr.Monk"))`.
- **What syncs:** SwiftData models (`FocusSession`, `Project`, `Preferences`).
- **Behavior:** CloudKit handles eventual consistency and conflict resolution (last‑writer‑wins by default).
- **Requirements:** Same Apple ID + iCloud enabled. Entitlements include the CloudKit container `iCloud.com.gbr.Monk` (`Monk/Monk.entitlements`).

## Live Session Mirroring (KVS + Screen Time)
Used to propagate “session started/stopped” quickly so the other device can mirror the session and apply hard blocking.

- **Service:** `MonkShared/Sources/MonkShared/Services/LiveSessionSyncService.swift`
- **Storage:** `NSUbiquitousKeyValueStore` (iCloud KVS).
- **Publisher:** `FocusManager.start(...)` → `liveSessionSync?.publishStart(session:)`  
  `FocusManager.stop()` → `liveSessionSync?.publishStop()`
- **Keys written:**  
  - `live.session.id` (UUID)  
  - `live.session.startedAt` (timestamp)  
  - `live.session.projectId` (UUID)  
  - `live.session.selectionData` (Screen Time selection)  
  - `live.session.updatedAt` (Date)  
  - `live.session.active` (Bool)
- **Receiver flow:**  
  - Observes `NSUbiquitousKeyValueStore.didChangeExternallyNotification`.  
  - Ignores stale updates > 180 seconds.  
  - On **stop**: deactivates hard block and ends mirrored session.  
  - On **start**: fetches project by id, applies selection data, activates hard block, inserts a mirrored `FocusSession` with the same UUID/start time, and schedules a local notification prompt (“Mirror your focus session”).
- **Platform gating:** Compiles only when `FamilyControls` + `ManagedSettings` are available (iOS/iPadOS). Stubbed out on other platforms.

## Entitlement Sync (KVS)
Used to share “Pro” access between devices after RevenueCat confirms entitlement.

- **Service:** `MonkShared/Sources/MonkShared/Services/EntitlementSyncService.swift`
- **Storage:** `NSUbiquitousKeyValueStore`
- **Keys written:**  
  - `entitlement.isEntitled`  
  - `entitlement.updatedAt`  
  - `entitlement.userId`  
  - `entitlement.source`
- **Usage:** UI gating checks `revenueCat.isPro || entitlementSync.isEntitled`.

## What’s NOT happening
- No backend server or push notifications to drive live sync.
- No local‑network/peer‑to‑peer sync.
- Live Activities do **not** sync between devices.
- The app does register for remote notifications, but there is no backend sending any.

## Debug/Notes
- Live session mirroring requires that projects are already synced on the receiver; otherwise it logs “project not found locally.”
- Staleness window for KVS live session updates is 180 seconds.
- If notifications are disabled, the mirror prompt won’t appear even if shielding is applied.
