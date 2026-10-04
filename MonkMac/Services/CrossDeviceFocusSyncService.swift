import CloudKit
import Combine
import Foundation
import OSLog

@MainActor
protocol FocusPolicySyncing: AnyObject {
    func publish(_ policy: FocusPolicy)
    func end(_ policy: FocusPolicy)
    func publishDefaultAccess(
        enabled: Bool,
        alwaysAllowedApplications: [ApplicationDescriptor]
    )
}

struct SyncedDefaultAccessConfiguration: Equatable {
    let enabled: Bool
    let applications: [CrossDeviceApplication]
    let updatedAt: Date

    init(enabled: Bool, applications: [CrossDeviceApplication], updatedAt: Date) {
        self.enabled = enabled
        self.applications = applications
        self.updatedAt = updatedAt
    }

    init?(record: CKRecord) {
        guard record.recordType == CrossDeviceCloudRecord.defaultAccessType,
              let enabledNumber = record["enabled"] as? NSNumber,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        enabled = enabledNumber.boolValue
        let ids = record["applicationIDs"] as? [String] ?? []
        let names = record["applicationNames"] as? [String] ?? []
        let bundleIdentifiers = record["applicationBundleIdentifiers"] as? [String] ?? []
        applications = ids.indices.compactMap { index in
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
        self.updatedAt = updatedAt
    }
}

struct SyncedFocusCommitment: Equatable {
    let sessionID: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let allowedDomains: [String]
    let allowedApplications: [CrossDeviceApplication]
    let isEnded: Bool

    init(
        sessionID: UUID,
        intention: String,
        startedAt: Date,
        endsAt: Date,
        allowedDomains: [String],
        allowedApplications: [CrossDeviceApplication] = [],
        isEnded: Bool = false
    ) {
        self.sessionID = sessionID
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.allowedDomains = allowedDomains
        self.allowedApplications = allowedApplications
        self.isEnded = isEnded
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
        isEnded = (record["sessionStatus"] as? String) == "ended"
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
    var onReceivedDefaultAccess: ((SyncedDefaultAccessConfiguration) -> Void)?

    private let applicationCatalog: ApplicationCatalog
    private let container = CKContainer(identifier: MonkConfiguration.cloudKitContainerIdentifier)
    private lazy var database = container.privateCloudDatabase
    private let logger = Logger(
        subsystem: MonkConfiguration.loggingSubsystem,
        category: "CrossDeviceFocus"
    )
    private var pollingTask: Task<Void, Never>?
    private var lastDeliveredFingerprint: String?
    private var lastDeliveredDefaultAccessFingerprint: String?
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
            await self?.fetchDefaultAccess()
            await self?.fetchMobileApplicationCatalogs()
            var catalogPollCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.fetchLatestCommitment()
                await self?.fetchDefaultAccess()
                catalogPollCount += 1
                if catalogPollCount >= 6 {
                    catalogPollCount = 0
                    await self?.fetchMobileApplicationCatalogs()
                }
            }
        }
    }

    func publish(_ policy: FocusPolicy) {
        lastDeliveredFingerprint = Self.fingerprint(
            sessionID: policy.id,
            endsAt: policy.endsAt,
            isEnded: false
        )
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
            record["sessionStatus"] = "active" as CKRecordValue

            do {
                _ = try await database.save(record)
                logger.notice("Published focus \(policy.id.uuidString, privacy: .public) for cross-device enforcement")
            } catch {
                logger.error("Cross-device focus publish failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func end(_ policy: FocusPolicy) {
        lastDeliveredFingerprint = Self.fingerprint(
            sessionID: policy.id,
            endsAt: policy.endsAt,
            isEnded: true
        )
        Task {
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentFocusName)
            let record = await recordForUpdate(type: Self.recordType, id: recordID)
            record["sessionID"] = policy.id.uuidString as CKRecordValue
            record["intention"] = policy.intention as CKRecordValue
            record["startedAt"] = policy.startedAt as CKRecordValue
            record["endsAt"] = policy.endsAt as CKRecordValue
            record["sourcePlatform"] = "macOS" as CKRecordValue
            record["sessionStatus"] = "ended" as CKRecordValue
            do {
                _ = try await database.save(record)
                logger.notice("Published end for focus \(policy.id.uuidString, privacy: .public)")
            } catch {
                logger.error("Cross-device focus end failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func publishDefaultAccess(
        enabled: Bool,
        alwaysAllowedApplications: [ApplicationDescriptor]
    ) {
        let updatedAt = Date()
        let portableApplications = portableApplications(from: alwaysAllowedApplications)
        let configuration = SyncedDefaultAccessConfiguration(
            enabled: enabled,
            applications: portableApplications,
            updatedAt: updatedAt
        )
        lastDeliveredDefaultAccessFingerprint = Self.defaultAccessFingerprint(configuration)

        Task {
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentDefaultAccessName)
            let record = await recordForUpdate(
                type: CrossDeviceCloudRecord.defaultAccessType,
                id: recordID
            )
            record["enabled"] = NSNumber(value: enabled)
            record["updatedAt"] = updatedAt as CKRecordValue
            record["applicationIDs"] = portableApplications.map(\.id) as NSArray
            record["applicationNames"] = portableApplications.map(\.displayName) as NSArray
            record["applicationBundleIdentifiers"] = portableApplications.map {
                $0.sourceBundleIdentifier ?? ""
            } as NSArray
            record["sourcePlatform"] = "macOS" as CKRecordValue
            do {
                _ = try await database.save(record)
                logger.notice("Published default access with \(portableApplications.count, privacy: .public) allowed apps")
            } catch {
                logger.error("Default access publish failed: \(error.localizedDescription, privacy: .public)")
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

    private func portableApplications(
        from applications: [ApplicationDescriptor]
    ) -> [CrossDeviceApplication] {
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
            guard let latest = SyncedFocusCommitment(record: record) else { return }
            let fingerprint = Self.fingerprint(
                sessionID: latest.sessionID,
                endsAt: latest.endsAt,
                isEnded: latest.isEnded
            )
            guard fingerprint != lastDeliveredFingerprint else { return }
            lastDeliveredFingerprint = fingerprint
            onReceivedCommitment?(latest)
            logger.notice("Received focus \(latest.sessionID.uuidString, privacy: .public) from iCloud")
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            logger.error("Cross-device focus fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchDefaultAccess() async {
        do {
            guard try await container.accountStatus() == .available else { return }
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentDefaultAccessName)
            let record = try await database.record(for: recordID)
            guard let configuration = SyncedDefaultAccessConfiguration(record: record) else { return }
            let fingerprint = Self.defaultAccessFingerprint(configuration)
            guard fingerprint != lastDeliveredDefaultAccessFingerprint else { return }
            lastDeliveredDefaultAccessFingerprint = fingerprint
            onReceivedDefaultAccess?(configuration)
            logger.notice("Received default access with \(configuration.applications.count, privacy: .public) allowed apps")
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            logger.error("Default access fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchMobileApplicationCatalogs() async {
        do {
            guard try await container.accountStatus() == .available else { return }
            let recordNames = [
                CrossDeviceCloudRecord.iPhoneApplicationCatalogName,
                CrossDeviceCloudRecord.iPadApplicationCatalogName
            ]
            var applications: [CrossDeviceApplication] = []
            for recordName in recordNames {
                let recordID = CKRecord.ID(recordName: recordName)
                do {
                    let record = try await database.record(for: recordID)
                    applications.append(contentsOf: Self.decodeApplicationCatalog(record))
                } catch let error as CKError where error.code == .unknownItem {
                    continue
                }
            }
            var seen = Set<String>()
            let uniqueApplications = applications.filter { seen.insert($0.id).inserted }
            applicationCatalog.setMobileApplications(uniqueApplications)
            logger.notice("Loaded \(uniqueApplications.count, privacy: .public) mobile applications from the private catalog")
        } catch {
            logger.error("Mobile application catalog fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decodeApplicationCatalog(_ record: CKRecord) -> [CrossDeviceApplication] {
        let ids = record["applicationIDs"] as? [String] ?? []
        let names = record["applicationNames"] as? [String] ?? []
        let bundleIdentifiers = record["applicationBundleIdentifiers"] as? [String] ?? []
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

    private static func fingerprint(
        sessionID: UUID,
        endsAt: Date,
        isEnded: Bool
    ) -> String {
        "\(sessionID.uuidString)|\(Int(endsAt.timeIntervalSince1970.rounded()))|\(isEnded)"
    }

    private static func defaultAccessFingerprint(
        _ configuration: SyncedDefaultAccessConfiguration
    ) -> String {
        let applicationIDs = configuration.applications.map(\.id).sorted().joined(separator: ",")
        return "\(configuration.enabled)|\(Int(configuration.updatedAt.timeIntervalSince1970.rounded()))|\(applicationIDs)"
    }
}
