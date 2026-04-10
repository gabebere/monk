import CloudKit
import Foundation
import OSLog
import SwiftData
import UserNotifications
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Handles emitting and receiving live session mirror events across devices using CloudKit subscriptions.
@MainActor
final class MirrorSyncService {
    static let shared = MirrorSyncService()

    private let container = CKContainer(identifier: "iCloud.com.gbr.Monk")
    private lazy var database = container.privateCloudDatabase
    private let subscriptionID = "session-mirror-events"
    private let participationKey = "mirroring.enabled"
    private let processedEventDefaultsKey = "mirror.processedEventIds"
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "MirrorSyncService")
    private var modelContainer: ModelContainer?
    private var notificationCenter: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    private let skewAllowance: TimeInterval = 30
    private var currentDeviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UIDevice.current.name
    }

    private init() {
        Task {
            await ensureSubscription()
            await purgeLegacyAlertNotifications()
        }
    }

    // MARK: - Public API

    func setParticipation(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: participationKey)
    }

    var isParticipating: Bool {
        UserDefaults.standard.object(forKey: participationKey) as? Bool ?? true
    }

    func setModelContainer(_ container: ModelContainer) {
        modelContainer = container
    }

    func emitStart(for session: FocusSession) async {
        guard isParticipating else { return }
        let payload = MirrorEventPayload(kind: .start,
                                         sessionId: session.id,
                                         sourceDeviceId: currentDeviceId,
                                         timestamp: session.startedAt,
                                         taskId: session.task?.id,
                                         taskTitle: session.task?.displayTitle,
                                         projectId: session.project?.id,
                                         projectTitle: session.project?.title,
                                         durationHintSeconds: nil)
        await save(payload: payload)
    }

    func emitStop(for session: FocusSession) async {
        guard isParticipating else { return }
        let duration = session.endedAt.map { max(0, $0.timeIntervalSince(session.startedAt)) }
        let payload = MirrorEventPayload(kind: .stop,
                                         sessionId: session.id,
                                         sourceDeviceId: currentDeviceId,
                                         timestamp: session.endedAt ?? Date(),
                                         taskId: session.task?.id,
                                         taskTitle: session.task?.displayTitle,
                                         projectId: session.project?.id,
                                         projectTitle: session.project?.title,
                                         durationHintSeconds: duration)
        await save(payload: payload)
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        guard isParticipating else { return }
        await purgeLegacyAlertNotifications()
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.subscriptionID == subscriptionID else {
            return
        }
        if let queryNotification = notification as? CKQueryNotification,
           let recordID = queryNotification.recordID {
            do {
                let record = try await database.record(for: recordID)
                await process(record: record)
            } catch {
                logger.error("Failed to fetch mirror record: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            // For database notifications without record IDs, fall back to a recent fetch.
            await fetchRecentMirrorEvents()
        }
    }

    // MARK: - Private helpers

    private func ensureSubscription() async {
        do {
            let all = try await database.allSubscriptions()
            var shouldCreateSubscription = true

            if let current = all.first(where: { $0.subscriptionID == subscriptionID }),
               let querySub = current as? CKQuerySubscription,
               isDesiredMirrorSubscription(querySub) {
                shouldCreateSubscription = false
            }

            for sub in all {
                let isCanonical = sub.subscriptionID == subscriptionID
                let isMirrorType = (sub as? CKQuerySubscription)?.recordType == MirrorEventPayload.recordType
                let isLegacyAlert = containsLegacyMirrorAlert(sub)

                if isCanonical {
                    if shouldCreateSubscription {
                        logger.debug("Replacing outdated mirror subscription \(sub.subscriptionID, privacy: .public)")
                        _ = try? await database.deleteSubscription(withID: sub.subscriptionID)
                    }
                    continue
                }

                if isMirrorType || isLegacyAlert {
                    logger.debug("Deleting legacy mirror subscription \(sub.subscriptionID, privacy: .public)")
                    _ = try? await database.deleteSubscription(withID: sub.subscriptionID)
                }
            }

            guard shouldCreateSubscription else {
                logger.debug("Mirror subscription already configured")
                return
            }

            let subscription = CKQuerySubscription(recordType: MirrorEventPayload.recordType,
                                                   predicate: NSPredicate(value: true),
                                                   subscriptionID: subscriptionID,
                                                   options: [.firesOnRecordCreation])
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true // silent push only
            subscription.notificationInfo = info

            _ = try await database.save(subscription)
            logger.debug("Mirror subscription created")
        } catch {
            logger.error("Failed to ensure mirror subscription: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isDesiredMirrorSubscription(_ subscription: CKQuerySubscription) -> Bool {
        guard subscription.recordType == MirrorEventPayload.recordType else { return false }
        let info = subscription.notificationInfo
        return info?.shouldSendContentAvailable == true &&
            info?.alertBody == nil &&
            info?.title == nil &&
            info?.subtitle == nil
    }

    private func containsLegacyMirrorAlert(_ subscription: CKSubscription) -> Bool {
        let alertBody = subscription.notificationInfo?.alertBody?.lowercased() ?? ""
        let title = subscription.notificationInfo?.title?.lowercased() ?? ""
        let subtitle = subscription.notificationInfo?.subtitle?.lowercased() ?? ""
        return alertBody.contains("mirror your focus session") ||
            title.contains("mirror your focus session") ||
            subtitle.contains("mirror your focus session")
    }

    /// Remove any pending/delivered legacy notifications that used alert text.
    private func purgeLegacyAlertNotifications() async {
        let targets = await withCheckedContinuation { continuation in
            notificationCenter.getDeliveredNotifications { delivered in
                continuation.resume(returning: delivered)
            }
        }
        let legacyIds = targets
            .filter { notif in
                let body = notif.request.content.body.lowercased()
                let title = notif.request.content.title.lowercased()
                return body.contains("mirror your focus session") || title.contains("mirror your focus session")
            }
            .map { $0.request.identifier }
        if !legacyIds.isEmpty {
            notificationCenter.removeDeliveredNotifications(withIdentifiers: legacyIds)
            notificationCenter.removePendingNotificationRequests(withIdentifiers: legacyIds)
            logger.debug("Purged \(legacyIds.count, privacy: .public) legacy mirror notifications")
        }
    }

    private func save(payload: MirrorEventPayload) async {
        let recordID = CKRecord.ID(recordName: payload.eventId.uuidString)
        let record = CKRecord(recordType: MirrorEventPayload.recordType, recordID: recordID)
        payload.encode(into: record)
        do {
            _ = try await database.save(record)
        } catch {
            logger.error("Failed to save mirror event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func process(record: CKRecord) async {
        guard let payload = MirrorEventPayload(record: record) else {
            logger.error("Mirror record decode failed")
            return
        }
        if payload.isExpired { return }
        if isDuplicate(eventId: payload.eventId) { return }
        markProcessed(eventId: payload.eventId)

        await handle(payload: payload)
    }

    private func handle(payload: MirrorEventPayload) async {
        guard let context = modelContainer.map(ModelContext.init) else {
            logger.error("Mirror handling skipped: missing model container")
            return
        }
        do {
            switch payload.kind {
            case .start:
                try await handleStart(payload: payload, context: context)
            case .stop:
                try await handleStop(payload: payload, context: context)
            }
        } catch {
            logger.error("Mirror handling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleStart(payload: MirrorEventPayload, context: ModelContext) async throws {
        // Ignore echoes from this device.
        if payload.sourceDeviceId == currentDeviceId {
            return
        }

        if let active = try fetchActiveSession(context: context) {
            // Latest wins by arrival: end current and replace.
            active.endedAt = Date()
            _ = context.saveOrRollback()
            HardBlockManager.shared.deactivateHardBlock()
#if canImport(ActivityKit)
            if #available(iOS 16.2, *) {
                LiveActivityManager.shared.endActivity(for: active)
            }
#endif
        }

        let session = FocusSession(
            id: payload.sessionId,
            startedAt: clampStartDate(payload.timestamp),
            endedAt: nil,
            project: try resolveProject(id: payload.projectId, context: context),
            task: try resolveTask(id: payload.taskId, context: context)
        )
        context.insert(session)
        guard context.saveOrRollback() else {
            logger.error("Mirror start failed to save session")
            return
        }

        let activated: Bool = {
            if let task = session.task,
               HardBlockManager.shared.activateFocusTools(for: task) {
                return true
            }
            if let project = session.project {
                return HardBlockManager.shared.activateHardBlock(for: project)
            }
            return false
        }()
        if (session.task != nil || session.project != nil) && !activated {
            await scheduleShieldFailureNotification(reason: "Open Monk to enforce shields for your mirrored session.")
        }
        SnapshotWriter.refresh(modelContext: context, currentSession: session)
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.startActivity(for: session, focusSnapshot: nil)
        }
#endif
        await FocusNudgeScheduler.shared.refresh(
            modelContext: context,
            currentSession: session,
            reason: "mirror_start"
        )
        NotificationCenter.default.post(name: .mirrorSessionDidChange, object: session.id)
        logger.debug("Mirrored session started \(session.id.uuidString, privacy: .public)")
    }

    private func handleStop(payload: MirrorEventPayload, context: ModelContext) async throws {
        // Ignore echoes from this device.
        if payload.sourceDeviceId == currentDeviceId {
            return
        }

        // Ignore stop if there is a newer local session.
        if let active = try fetchActiveSession(context: context),
           active.startedAt > payload.timestamp.addingTimeInterval(skewAllowance) {
            logger.debug("Mirror stop ignored: local session newer")
            return
        }

        guard let session = try resolveSessionToStop(payload: payload, context: context) else {
            logger.debug("Mirror stop: no matching session found; lifting shields if active")
            HardBlockManager.shared.deactivateHardBlock()
#if canImport(ActivityKit)
            if #available(iOS 16.2, *) {
                LiveActivityManager.shared.endActivity()
            }
#endif
            return
        }
        session.endedAt = Date()
        if context.saveOrRollback() {
            HardBlockManager.shared.deactivateHardBlock()
            SnapshotWriter.refresh(modelContext: context, currentSession: session, stateOverride: .stopped)
#if canImport(ActivityKit)
            if #available(iOS 16.2, *) {
                LiveActivityManager.shared.endActivity(for: session)
            }
#endif
            await FocusNudgeScheduler.shared.refresh(
                modelContext: context,
                currentSession: nil,
                reason: "mirror_stop"
            )
            NotificationCenter.default.post(name: .mirrorSessionDidChange, object: session.id)
            logger.debug("Mirrored session stopped \(session.id.uuidString, privacy: .public)")
        } else {
            logger.error("Mirror stop failed to save")
        }
    }

    private func fetchActiveSession(context: ModelContext) throws -> FocusSession? {
        var descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { session in session.endedAt == nil })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func resolveProject(id: UUID?, context: ModelContext) throws -> Project? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in project.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func resolveTask(id: UUID?, context: ModelContext) throws -> FocusTask? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<FocusTask>(predicate: #Predicate { task in task.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func resolveSessionToStop(payload: MirrorEventPayload, context: ModelContext) throws -> FocusSession? {
        if let match = try fetchSession(by: payload.sessionId, context: context, onlyActive: true) {
            return match
        }
        if let taskId = payload.taskId,
           let byTask = try fetchSession(byTask: taskId, context: context) {
            return byTask
        }
        if let projectId = payload.projectId,
           let byProject = try fetchSession(byProject: projectId, context: context) {
            return byProject
        }
        return nil
    }

    private func fetchSession(by id: UUID, context: ModelContext, onlyActive: Bool) throws -> FocusSession? {
        var descriptor: FetchDescriptor<FocusSession>
        if onlyActive {
            descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate<FocusSession> { session in
                session.id == id && session.endedAt == nil
            })
        } else {
            descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate<FocusSession> { session in
                session.id == id
            })
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchSession(byTask taskId: UUID, context: ModelContext) throws -> FocusSession? {
        let predicate = #Predicate<FocusSession> { session in
            session.task?.id == taskId && session.endedAt == nil
        }
        var descriptor = FetchDescriptor<FocusSession>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchSession(byProject projectId: UUID, context: ModelContext) throws -> FocusSession? {
        let predicate = #Predicate<FocusSession> { session in
            session.project?.id == projectId && session.endedAt == nil
        }
        var descriptor = FetchDescriptor<FocusSession>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func clampStartDate(_ date: Date) -> Date {
        let now = Date()
        if date > now { return now }
        let tooOld = now.addingTimeInterval(-TimeInterval(MirrorEventPayload.ttlSeconds))
        return max(date, tooOld)
    }

    private func scheduleShieldFailureNotification(reason: String) async {
        let status = await notificationCenter.notificationSettings()
        guard status.authorizationStatus == .authorized || status.authorizationStatus == .provisional else { return }

        // Clear any previous shield failure notifications to avoid duplicates.
        let pending = await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
        let identifiers = pending.map { $0.identifier }.filter { $0.hasPrefix("mirror.shieldFailure") }
        if !identifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        let content = UNMutableNotificationContent()
        content.title = "Open Monk to finish shield setup."
        content.body = reason
        content.sound = .default

        let request = UNNotificationRequest(identifier: "mirror.shieldFailure.\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
        do {
            try await notificationCenter.add(request)
        } catch {
            logger.error("Failed to schedule shield failure notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchRecentMirrorEvents() async {
        let query = CKQuery(recordType: MirrorEventPayload.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        do {
            let result = try await database.records(matching: query, desiredKeys: nil)
            for (_, recordResult) in result.matchResults {
                switch recordResult {
                case .success(let record):
                    await process(record: record)
                case .failure(let error):
                    logger.error("Mirror event fetch item failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            logger.error("Failed to fetch recent mirror events: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isDuplicate(eventId: UUID) -> Bool {
        let defaults = UserDefaults.standard
        let set = defaults.array(forKey: processedEventDefaultsKey) as? [String] ?? []
        return set.contains(eventId.uuidString)
    }

    private func markProcessed(eventId: UUID) {
        let defaults = UserDefaults.standard
        var set = defaults.array(forKey: processedEventDefaultsKey) as? [String] ?? []
        set.append(eventId.uuidString)
        // Keep it small
        if set.count > 128 { set = Array(set.suffix(64)) }
        defaults.set(set, forKey: processedEventDefaultsKey)
    }
}

// MARK: - Payload mapping

private struct MirrorEventPayload {
    enum Kind: String {
        case start
        case stop
    }

    static let recordType = "SessionMirrorEvent"
    static let ttlSeconds: Int = 300

    let eventId: UUID
    let sessionId: UUID
    let kind: Kind
    let sourceDeviceId: String
    let timestamp: Date
    let taskId: UUID?
    let taskTitle: String?
    let projectId: UUID?
    let projectTitle: String?
    let durationHintSeconds: Double?
    var isExpired: Bool {
        let expiry = timestamp.addingTimeInterval(TimeInterval(MirrorEventPayload.ttlSeconds))
        return expiry < Date().addingTimeInterval(-30) // small skew allowance
    }

    init(kind: Kind,
         sessionId: UUID,
         sourceDeviceId: String,
         timestamp: Date,
         taskId: UUID?,
         taskTitle: String?,
         projectId: UUID?,
         projectTitle: String?,
         durationHintSeconds: Double?) {
        self.eventId = UUID()
        self.kind = kind
        self.sourceDeviceId = sourceDeviceId
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.projectId = projectId
        self.projectTitle = projectTitle
        self.durationHintSeconds = durationHintSeconds
    }

    init?(record: CKRecord) {
        guard
            let kindRaw = record["kind"] as? String,
            let kind = Kind(rawValue: kindRaw),
            let sessionIdString = record["sessionId"] as? String,
            let sessionId = UUID(uuidString: sessionIdString),
            let timestamp = record["timestamp"] as? Date,
            let sourceDeviceId = record["sourceDeviceId"] as? String
        else { return nil }

        let eventIdString = (record["eventId"] as? String) ?? record.recordID.recordName
        guard let eventId = UUID(uuidString: eventIdString) else { return nil }

        self.eventId = eventId
        self.kind = kind
        self.sourceDeviceId = sourceDeviceId
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.taskId = (record["taskId"] as? String).flatMap(UUID.init(uuidString:))
        self.taskTitle = record["taskTitle"] as? String
        self.projectId = (record["projectId"] as? String).flatMap(UUID.init(uuidString:))
        self.projectTitle = record["projectTitle"] as? String
        self.durationHintSeconds = record["durationHintSeconds"] as? Double
    }

    func encode(into record: CKRecord) {
        record["eventId"] = eventId.uuidString as CKRecordValue
        record["sessionId"] = sessionId.uuidString as CKRecordValue
        record["kind"] = kind.rawValue as CKRecordValue
        record["sourceDeviceId"] = sourceDeviceId as CKRecordValue
        record["timestamp"] = timestamp as CKRecordValue
        if let taskId { record["taskId"] = taskId.uuidString as CKRecordValue }
        if let taskTitle { record["taskTitle"] = taskTitle as CKRecordValue }
        if let projectId { record["projectId"] = projectId.uuidString as CKRecordValue }
        if let projectTitle { record["projectTitle"] = projectTitle as CKRecordValue }
        if let durationHintSeconds {
            record["durationHintSeconds"] = durationHintSeconds as CKRecordValue
        }
        record["ttlSeconds"] = MirrorEventPayload.ttlSeconds as CKRecordValue
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let mirrorSessionDidChange = Notification.Name("mirrorSessionDidChange")
}
