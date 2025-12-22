#if canImport(FamilyControls) && canImport(ManagedSettings)
import Foundation
import SwiftData
import FamilyControls
@preconcurrency import UserNotifications

/// Syncs live session start/stop state via iCloud KVS so other devices can activate/deactivate Screen Time shields quickly.
@MainActor
public final class LiveSessionSyncService: ObservableObject {

    private enum Keys {
        static let sessionId = "live.session.id"
        static let startedAt = "live.session.startedAt"
        static let projectId = "live.session.projectId"
        static let selectionData = "live.session.selectionData"
        static let updatedAt = "live.session.updatedAt"
        static let isActive = "live.session.active"
    }

    private let store: NSUbiquitousKeyValueStore
    private let modelContext: ModelContext
    private let staleness: TimeInterval = 180 // 3 minutes

    public init(modelContext: ModelContext,
                store: NSUbiquitousKeyValueStore = .default) {
        self.modelContext = modelContext
        self.store = store
        print("[LiveSessionSync] init")
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onStoreChanged(_:)),
                                               name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: store)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func publishStart(session: FocusSession) {
        guard let project = session.project else { return }
        store.set(session.id.uuidString, forKey: Keys.sessionId)
        store.set(session.startedAt.timeIntervalSince1970, forKey: Keys.startedAt)
        store.set(project.id.uuidString, forKey: Keys.projectId)
        if let data = project.hardBlockSelectionData {
            store.set(data, forKey: Keys.selectionData)
        } else {
            store.removeObject(forKey: Keys.selectionData)
        }
        store.set(Date(), forKey: Keys.updatedAt)
        store.set(true, forKey: Keys.isActive)
        store.synchronize()
    }

    public func publishStop() {
        store.set(Date(), forKey: Keys.updatedAt)
        store.set(false, forKey: Keys.isActive)
        // Keep sessionId/startedAt for receivers to close matching sessions.
        store.synchronize()
        HardBlockManager.shared.deactivateHardBlock()
    }

    @objc private func onStoreChanged(_ note: Notification) {
        guard let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              reason == NSUbiquitousKeyValueStoreServerChange ||
              reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }
        Task { @MainActor in
            self.handleRemoteUpdate()
        }
    }

    private func handleRemoteUpdate() {
        let isActive = store.bool(forKey: Keys.isActive)
        guard let updatedAt = store.object(forKey: Keys.updatedAt) as? Date else { return }
        let delta = abs(updatedAt.timeIntervalSinceNow)
        print("[LiveSessionSync] handleRemoteUpdate isActive=\(isActive) updatedAt=\(updatedAt) delta=\(delta)s")
        if delta > staleness {
            print("[LiveSessionSync] stale update skipped")
            return
        }

        if !isActive {
            HardBlockManager.shared.deactivateHardBlock()
            endMirroredSession()
            return
        }

        guard let projectIdString = store.string(forKey: Keys.projectId),
              let projectId = UUID(uuidString: projectIdString) else { return }

        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        guard let project = (try? modelContext.fetch(descriptor))?.first else {
            print("[LiveSessionSync] project not found locally for id \(projectId)")
            return
        }
        print("[LiveSessionSync] fetched project \(project.title)")

        if let data = store.data(forKey: Keys.selectionData) {
            project.hardBlockSelectionData = data
            _ = modelContext.saveOrRollback()
        }
        _ = HardBlockManager.shared.activateHardBlock(for: project)
        startMirroredSession(project: project)
    }

    private func startMirroredSession(project: Project) {
        guard let sessionIdString = store.string(forKey: Keys.sessionId),
              let sessionId = UUID(uuidString: sessionIdString) else { return }
        if let existing = fetchSession(id: sessionId), existing.endedAt == nil {
            print("[LiveSessionSync] existing mirrored session already in progress \(sessionId)")
            return // already mirrored or running locally
        }
        if let existingInProgress = fetchInProgressSession() {
            // Another session is running locally; don't overwrite.
            if existingInProgress.id != sessionId {
                print("[LiveSessionSync] another session already running locally id=\(existingInProgress.id)")
                return
            }
        }
        let startedAtInterval = store.object(forKey: Keys.startedAt) as? TimeInterval ?? Date().timeIntervalSince1970
        let startedAt = Date(timeIntervalSince1970: startedAtInterval)
        print("[LiveSessionSync] startMirroredSession id=\(sessionId) startedAt=\(startedAt)")
        let newSession = FocusSession(id: sessionId, startedAt: startedAt, endedAt: nil, project: project)
        modelContext.insert(newSession)
        _ = modelContext.saveOrRollback()
        schedulePrompt()
    }

    private func endMirroredSession() {
        guard let sessionIdString = store.string(forKey: Keys.sessionId),
              let sessionId = UUID(uuidString: sessionIdString) else { return }
        guard let session = fetchSession(id: sessionId) else { return }
        if session.endedAt == nil {
            session.endedAt = Date()
            _ = modelContext.saveOrRollback()
        }
    }

    private func fetchSession(id: UUID) -> FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchInProgressSession() -> FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.endedAt == nil })
        return (try? modelContext.fetch(descriptor))?.first
    }
 
    private func schedulePrompt() {
        print("[LiveSessionSync] scheduling prompt")
        let content = UNMutableNotificationContent()
        content.title = "Mirror your focus session"
        content.body = "Tap to mirror your current session to this device and apply blocking."
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let identifier = "live_session_mirror_prompt_\(UUID().uuidString)"
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("[LiveSessionSync] notification settings authStatus=\(settings.authorizationStatus.rawValue)")
            Task { @MainActor in
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                do {
                    try await UNUserNotificationCenter.current().add(request)
                    print("[LiveSessionSync] prompt scheduled")
                } catch {
                    print("[LiveSessionSync] prompt add error: \(error.localizedDescription)")
                }
            }
        }
    }

    // Debug helper
    public func triggerPromptDebug() {
        schedulePrompt()
    }
}
#else
import SwiftData

// Stub for platforms without Screen Time frameworks.
public final class LiveSessionSyncService {
    public init(modelContext: ModelContext) {}
    public func publishStart(session: FocusSession) {}
    public func publishStop() {}
}
#endif
