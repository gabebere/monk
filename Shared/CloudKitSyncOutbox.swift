import CloudKit
import Foundation
import OSLog

extension FocusSyncState {
    init?(record: CKRecord) {
        guard record.recordType == CrossDeviceCloudRecord.focusType,
              let rawID = record["sessionID"] as? String,
              let sessionID = UUID(uuidString: rawID),
              let intention = record["intention"] as? String,
              let startedAt = record["startedAt"] as? Date,
              let endsAt = record["endsAt"] as? Date,
              endsAt >= startedAt else { return nil }
        self.init(sessionID: sessionID, intention: intention, startedAt: startedAt, endsAt: endsAt,
                  allowedDomains: record["allowedDomains"] as? [String] ?? [],
                  allowedApplications: Self.applications(in: record, prefix: "allowedApplication"),
                  sourcePlatform: record["sourcePlatform"] as? String,
                  isEnded: (record["sessionStatus"] as? String) == "ended")
    }

    func write(to record: CKRecord) {
        record["sessionID"] = sessionID.uuidString as CKRecordValue
        record["intention"] = intention as CKRecordValue
        record["startedAt"] = startedAt as CKRecordValue
        record["endsAt"] = endsAt as CKRecordValue
        record["allowedDomains"] = allowedDomains as NSArray
        record["allowedApplicationIDs"] = allowedApplications.map(\.id) as NSArray
        record["allowedApplicationNames"] = allowedApplications.map(\.displayName) as NSArray
        record["allowedApplicationBundleIdentifiers"] = allowedApplications.map { $0.sourceBundleIdentifier ?? "" } as NSArray
        if let sourcePlatform { record["sourcePlatform"] = sourcePlatform as CKRecordValue }
        else { record["sourcePlatform"] = nil }
        record["sessionStatus"] = (isEnded ? "ended" : "active") as CKRecordValue
    }

    static func applications(in record: CKRecord, prefix: String) -> [CrossDeviceApplication] {
        let ids = record["\(prefix)IDs"] as? [String] ?? []
        let names = record["\(prefix)Names"] as? [String] ?? []
        let bundles = record["\(prefix)BundleIdentifiers"] as? [String] ?? []
        return ids.indices.compactMap { index in
            guard names.indices.contains(index) else { return nil }
            let bundle = bundles.indices.contains(index) && !bundles[index].isEmpty ? bundles[index] : nil
            return CrossDeviceApplication(id: ids[index], displayName: names[index], sourceBundleIdentifier: bundle)
        }
    }
}

extension DefaultAccessSyncState {
    init?(record: CKRecord) {
        guard record.recordType == CrossDeviceCloudRecord.defaultAccessType,
              let enabled = record["enabled"] as? NSNumber,
              let updatedAt = record["updatedAt"] as? Date else { return nil }
        let applications = FocusSyncState.applications(in: record, prefix: "application")
        self.init(enabled: enabled.boolValue,
                  applications: applications,
                  updatedAt: updatedAt,
                  applicationsAreAuthoritative: (record["applicationsAreAuthoritative"] as? NSNumber)?.boolValue ?? !applications.isEmpty,
                  sourcePlatform: record["sourcePlatform"] as? String ?? "unknown")
    }
}

/// Account-bound, durable pending state. Nothing is uploaded until the current iCloud identity
/// has been verified. Changing accounts discards outgoing state and invalidates in-flight work.
@MainActor
final class CloudKitSyncOutbox {
    private let container: CKContainer
    private let fileURL: URL
    private var journal: CloudKitSyncJournal
    private var isFlushing = false
    private var failures = 0
    private var nextAttempt = Date.distantPast
    private(set) var generation = 0
    private(set) var verifiedAccountID: String?
    private(set) var lastError: String?
    private let logger = Logger(subsystem: MonkConfiguration.loggingSubsystem, category: "SyncOutbox")

    var pendingDefaultAccess: DefaultAccessSyncState? {
        journal.pending.first { $0.defaultAccess != nil }?.defaultAccess
    }

    init(container: CKContainer, fileURL: URL? = nil) {
        self.container = container
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Monk", isDirectory: true)
            .appendingPathComponent("cloudkit-outbox.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let stored = try? JSONDecoder().decode(CloudKitSyncJournal.self, from: data) {
            journal = stored
        } else {
            journal = CloudKitSyncJournal()
        }
    }

    func accountDidChange() {
        generation += 1
        verifiedAccountID = nil
        // Keep outgoing data quarantined under its verified owner until identity is
        // known again. A transient sign-out must not lose the same account's writes.
        failures = 0
        nextAttempt = .distantPast
        try? persist()
    }

    @discardableResult
    func verifyAccount() async throws -> Int {
        let expected = generation
        guard try await container.accountStatus() == .available else {
            verifiedAccountID = nil
            throw CKError(.notAuthenticated)
        }
        let accountID = try await container.userRecordID().recordName
        guard expected == generation else { throw CancellationError() }
        if let previous = journal.accountID, previous != accountID {
            generation += 1
            failures = 0
            nextAttempt = .distantPast
        }
        journal.bind(to: accountID)
        verifiedAccountID = accountID
        try persist()
        return generation
    }

    func quarantineUnownedRestoredFocus(sessionID: UUID) {
        journal.quarantineUnownedRestore(sessionID: sessionID)
        try? persist()
    }

    func rememberReceivedFocus(_ focus: FocusSyncState, generation expected: Int) {
        guard expected == generation, let accountID = verifiedAccountID else { return }
        if journal.sessionAccountIDs[focus.sessionID.uuidString] == nil {
            journal.remember(sessionID: focus.sessionID, accountID: accountID)
            try? persist()
        }
    }

    func enqueue(_ mutation: CloudKitSyncMutation) {
        journal.enqueue(mutation)
        do {
            try persist()
            lastError = nil
        } catch {
            lastError = "Could not save pending sync changes"
            logger.error("Unable to persist outgoing state: \(error.localizedDescription, privacy: .public)")
        }
    }

    func flush() async {
        guard !isFlushing, Date() >= nextAttempt, !journal.pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }
        do {
            let expected = try await verifyAccount()
            while let mutation = journal.pending.first {
                guard expected == generation else { return }
                try await save(mutation, generation: expected)
                guard expected == generation else { return }
                journal.pending.removeAll { $0.id == mutation.id }
                try persist()
            }
            failures = 0
            nextAttempt = .distantPast
            lastError = nil
        } catch {
            if error is CancellationError { return }
            failures = min(failures + 1, 8)
            let retryAfter = (error as? CKError)?.retryAfterSeconds ?? 0
            nextAttempt = Date().addingTimeInterval(max(retryAfter, min(300, pow(2, Double(failures)))))
            lastError = "Changes are saved on this device and will sync when iCloud is available"
            logger.error("Pending sync will retry: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save(_ mutation: CloudKitSyncMutation, generation expected: Int) async throws {
        let database = container.privateCloudDatabase
        let isFocus = mutation.focus != nil
        let name = isFocus ? CrossDeviceCloudRecord.currentFocusName : CrossDeviceCloudRecord.currentDefaultAccessName
        let type = isFocus ? CrossDeviceCloudRecord.focusType : CrossDeviceCloudRecord.defaultAccessType
        let id = CKRecord.ID(recordName: name)
        // Fetch a fresh change tag after a competing write. Every retry re-evaluates the policy.
        for _ in 0..<3 {
            let record: CKRecord
            do { record = try await database.record(for: id) }
            catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: type, recordID: id)
            }
            guard expected == generation else { throw CancellationError() }
            if let focus = mutation.focus {
                if let existing = FocusSyncState(record: record),
                   FocusSyncState.resolve(existing, focus, now: .now) == existing { return }
                guard !focus.isEnded || focus.endsAt <= .now else { return }
                focus.write(to: record)
            } else if let defaults = mutation.defaultAccess {
                if let existing = DefaultAccessSyncState(record: record),
                   DefaultAccessSyncState.resolve(existing, defaults) == existing { return }
                record["enabled"] = NSNumber(value: defaults.enabled)
                record["updatedAt"] = defaults.updatedAt as CKRecordValue
                record["applicationsAreAuthoritative"] = NSNumber(value: defaults.applicationsAreAuthoritative)
                if defaults.applicationsAreAuthoritative {
                    record["applicationIDs"] = defaults.applications.map(\.id) as NSArray
                    record["applicationNames"] = defaults.applications.map(\.displayName) as NSArray
                    record["applicationBundleIdentifiers"] = defaults.applications.map { $0.sourceBundleIdentifier ?? "" } as NSArray
                }
                record["sourcePlatform"] = defaults.sourcePlatform as CKRecordValue
            }
            guard expected == generation else { throw CancellationError() }
            do {
                _ = try await database.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            }
        }
        throw CKError(.serverRecordChanged)
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(journal)
        try data.write(to: fileURL, options: .atomic)
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
