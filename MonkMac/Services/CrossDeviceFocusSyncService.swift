import CloudKit
import Combine
import Foundation
import OSLog

@MainActor
protocol FocusPolicySyncing: AnyObject {
    func publish(_ policy: FocusPolicy)
}

struct SyncedFocusCommitment: Equatable {
    let sessionID: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let allowedDomains: [String]
    let allowedApplications: [CrossDeviceApplication]

    init(
        sessionID: UUID,
        intention: String,
        startedAt: Date,
        endsAt: Date,
        allowedDomains: [String],
        allowedApplications: [CrossDeviceApplication] = []
    ) {
        self.sessionID = sessionID
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.allowedDomains = allowedDomains
        self.allowedApplications = allowedApplications
    }

    init?(record: CKRecord) {
        guard record.recordType == CrossDeviceFocusSyncService.recordType,
              let sessionIDString = record["sessionID"] as? String,
              let sessionID = UUID(uuidString: sessionIDString),
              let intention = record["intention"] as? String,
              let startedAt = record["startedAt"] as? Date,
              let endsAt = record["endsAt"] as? Date else {
            return nil
        }

        self.sessionID = sessionID
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = endsAt
        allowedDomains = record["allowedDomains"] as? [String] ?? []
        allowedApplications = Self.decodeApplications(from: record)
    }

    private static func decodeApplications(from record: CKRecord) -> [CrossDeviceApplication] {
        let ids = record["allowedApplicationIDs"] as? [String] ?? []
        let names = record["allowedApplicationNames"] as? [String] ?? []
        let bundleIdentifiers = record["allowedApplicationBundleIdentifiers"] as? [String] ?? []

        return ids.indices.compactMap { index in
            guard names.indices.contains(index) else { return nil }
            let bundleIdentifier = bundleIdentifiers.indices.contains(index) && !bundleIdentifiers[index].isEmpty
                ? bundleIdentifiers[index]
                : nil
            return CrossDeviceApplication(
                id: ids[index],
                displayName: names[index],
                sourceBundleIdentifier: bundleIdentifier
            )
        }
    }
}

@MainActor
final class CrossDeviceFocusSyncService: FocusPolicySyncing {
    nonisolated static let recordType = CrossDeviceCloudRecord.focusType

    var onReceivedCommitment: ((SyncedFocusCommitment) -> Void)?

    private let applicationCatalog: ApplicationCatalog
    private let container = CKContainer(identifier: "iCloud.com.gbr.Monk")
    private lazy var database = container.privateCloudDatabase
    private let logger = Logger(subsystem: "com.gbr.Monk.mac", category: "CrossDeviceFocus")
    private var pollingTask: Task<Void, Never>?
    private var lastDeliveredSessionID: UUID?
    private var catalogCancellable: AnyCancellable?

    init(applicationCatalog: ApplicationCatalog) {
        self.applicationCatalog = applicationCatalog
        catalogCancellable = applicationCatalog.$applications
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.publishApplicationCatalog()
                }
            }
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else { return }

        pollingTask = Task { @MainActor [weak self] in
            await self?.fetchLatestCommitment()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.fetchLatestCommitment()
            }
        }
    }

    func publish(_ policy: FocusPolicy) {
        Task {
            let allowedApplications = portableApplications(from: policy)
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentFocusName)
            let record = await recordForUpdate(type: Self.recordType, id: recordID)

            record["sessionID"] = policy.id.uuidString as CKRecordValue
            record["intention"] = policy.intention as CKRecordValue
            record["startedAt"] = policy.startedAt as CKRecordValue
            record["endsAt"] = policy.endsAt as CKRecordValue
            record["allowedDomains"] = policy.allowedDomains as NSArray
            record["allowedApplicationIDs"] = allowedApplications.map(\.id) as NSArray
            record["allowedApplicationNames"] = allowedApplications.map(\.displayName) as NSArray
            record["allowedApplicationBundleIdentifiers"] = allowedApplications.map { $0.sourceBundleIdentifier ?? "" } as NSArray
            record["sourcePlatform"] = "macOS" as CKRecordValue

            do {
                _ = try await database.save(record)
                logger.notice("Published focus \(policy.id.uuidString, privacy: .public) for cross-device enforcement")
            } catch {
                logger.error("Cross-device focus publish failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func portableApplications(from policy: FocusPolicy) -> [CrossDeviceApplication] {
        let applications = policy.allowedApplications.filter { application in
            guard !policy.allowedDomains.isEmpty,
                  let bundleIdentifier = application.bundleIdentifier else {
                return true
            }
            return SupportedBrowser.scriptingFamily(for: bundleIdentifier) == nil
        }

        var seen = Set<String>()
        return applications.compactMap { application in
            let portable = CrossDeviceApplication(
                displayName: application.displayName,
                bundleIdentifier: application.bundleIdentifier
            )
            return seen.insert(portable.id).inserted ? portable : nil
        }
    }

    private func fetchLatestCommitment() async {
        do {
            guard try await container.accountStatus() == .available else { return }
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentFocusName)
            let record = try await database.record(for: recordID)
            guard let latest = SyncedFocusCommitment(record: record),
                  latest.endsAt > .now,
                  latest.sessionID != lastDeliveredSessionID else { return }
            lastDeliveredSessionID = latest.sessionID
            onReceivedCommitment?(latest)
            logger.notice("Received focus \(latest.sessionID.uuidString, privacy: .public) from iCloud")
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            logger.error("Cross-device focus fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishApplicationCatalog() async {
        do {
            guard try await container.accountStatus() == .available else { return }
            let applications = portableCatalogApplications()
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.macApplicationCatalogName)
            let record = await recordForUpdate(
                type: CrossDeviceCloudRecord.applicationCatalogType,
                id: recordID
            )
            record["platform"] = "macOS" as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            record["applicationIDs"] = applications.map(\.id) as NSArray
            record["applicationNames"] = applications.map(\.displayName) as NSArray
            record["applicationBundleIdentifiers"] = applications.map {
                $0.sourceBundleIdentifier ?? ""
            } as NSArray
            _ = try await database.save(record)
            logger.notice("Published \(applications.count) Mac applications to the private catalog")
        } catch {
            logger.error("Mac application catalog publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func portableCatalogApplications() -> [CrossDeviceApplication] {
        var seen = Set<String>()
        return applicationCatalog.applications.prefix(500).compactMap { application in
            let portable = CrossDeviceApplication(
                displayName: application.displayName,
                bundleIdentifier: application.bundleIdentifier
            )
            return seen.insert(portable.id).inserted ? portable : nil
        }
    }

    private func recordForUpdate(type: String, id: CKRecord.ID) async -> CKRecord {
        do {
            return try await database.record(for: id)
        } catch {
            return CKRecord(recordType: type, recordID: id)
        }
    }
}
