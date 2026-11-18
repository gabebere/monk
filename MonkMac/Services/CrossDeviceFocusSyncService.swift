import CloudKit
import Combine
import Foundation
import OSLog

@MainActor
protocol FocusPolicySyncing: AnyObject {
    func publish(_ policy: FocusPolicy)
    func end(_ policy: FocusPolicy)
    func quarantineRestoredFocus(_ policy: FocusPolicy)
    func publishDefaultAccess(enabled: Bool, alwaysAllowedApplications: [ApplicationDescriptor])
}

extension FocusPolicySyncing {
    func quarantineRestoredFocus(_ policy: FocusPolicy) {}
}

typealias SyncedDefaultAccessConfiguration = DefaultAccessSyncState
typealias SyncedFocusCommitment = FocusSyncState

@MainActor
final class CrossDeviceFocusSyncService: FocusPolicySyncing {
    nonisolated static let recordType = CrossDeviceCloudRecord.focusType
    var onReceivedCommitment: ((SyncedFocusCommitment) -> Void)?
    var onReceivedDefaultAccess: ((SyncedDefaultAccessConfiguration) -> Void)?

    private let applicationCatalog: ApplicationCatalog
    private let container = CKContainer(identifier: MonkConfiguration.cloudKitContainerIdentifier)
    private lazy var database = container.privateCloudDatabase
    private lazy var outbox = CloudKitSyncOutbox(container: container)
    private let logger = Logger(subsystem: MonkConfiguration.loggingSubsystem, category: "CrossDeviceFocus")
    private var pollingTask: Task<Void, Never>?
    private var accountObserver: NSObjectProtocol?
    private var lastDeliveredFingerprint: String?
    private var lastDeliveredDefaultAccessFingerprint: String?
    private var catalogCancellable: AnyCancellable?

    init(applicationCatalog: ApplicationCatalog) {
        self.applicationCatalog = applicationCatalog
        catalogCancellable = applicationCatalog.$applications.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in await self?.publishApplicationCatalog() }
        }
    }

    deinit {
        pollingTask?.cancel()
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
    }

    func start() {
        guard pollingTask == nil else { return }
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.outbox.accountDidChange()
                self?.lastDeliveredFingerprint = nil
                self?.lastDeliveredDefaultAccessFingerprint = nil
                self?.applicationCatalog.setMobileApplications([])
            }
        }
        pollingTask = Task { @MainActor [weak self] in
            await self?.outbox.flush()
            await self?.fetchLatestCommitment()
            await self?.fetchDefaultAccess()
            await self?.fetchMobileApplicationCatalogs()
            await self?.publishApplicationCatalog()
            var catalogPollCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.outbox.flush()
                await self?.fetchLatestCommitment()
                await self?.fetchDefaultAccess()
                catalogPollCount += 1
                if catalogPollCount >= 6 {
                    catalogPollCount = 0
                    await self?.fetchMobileApplicationCatalogs()
                    await self?.publishApplicationCatalog()
                }
            }
        }
    }

    func quarantineRestoredFocus(_ policy: FocusPolicy) {
        outbox.quarantineUnownedRestoredFocus(sessionID: policy.id)
    }

    func publish(_ policy: FocusPolicy) {
        enqueue(policy, isEnded: false)
    }

    func end(_ policy: FocusPolicy) {
        guard policy.endsAt <= .now else { return }
        enqueue(policy, isEnded: true)
    }

    private func enqueue(_ policy: FocusPolicy, isEnded: Bool) {
        let state = FocusSyncState(
            sessionID: policy.id, intention: policy.intention, startedAt: policy.startedAt,
            endsAt: policy.endsAt, allowedDomains: policy.allowedDomains,
            allowedApplications: portableApplications(from: policy), sourcePlatform: "macOS",
            isEnded: isEnded
        )
        outbox.enqueue(CloudKitSyncMutation(focus: state))
        Task { await outbox.flush() }
    }

    func publishDefaultAccess(
        enabled: Bool,
        alwaysAllowedApplications: [ApplicationDescriptor]
    ) {
        let configuration = DefaultAccessSyncState(
            enabled: enabled, applications: portableApplications(from: alwaysAllowedApplications),
            updatedAt: Date(), sourcePlatform: "macOS"
        )
        outbox.enqueue(CloudKitSyncMutation(defaultAccess: configuration))
        Task { await outbox.flush() }
    }

    private func portableApplications(from policy: FocusPolicy) -> [CrossDeviceApplication] {
        if let portable = policy.portableAllowedApplications { return portable }
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
            let generation = try await outbox.verifyAccount()
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentFocusName)
            let record = try await database.record(for: recordID)
            guard generation == outbox.generation else { return }
            guard let latest = SyncedFocusCommitment(record: record) else { return }
            outbox.rememberReceivedFocus(latest, generation: generation)
            let fingerprint = Self.fingerprint(
                sessionID: latest.sessionID,
                endsAt: latest.endsAt,
                isEnded: latest.isEnded
            )
            // Re-deliver active state so a previously conflicting local commitment can converge.
            if !latest.isEnded || fingerprint != lastDeliveredFingerprint {
                lastDeliveredFingerprint = fingerprint
                onReceivedCommitment?(latest)
            }
            logger.notice("Received focus \(latest.sessionID.uuidString, privacy: .public) from iCloud")
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            logger.error("Cross-device focus fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchDefaultAccess() async {
        do {
            let generation = try await outbox.verifyAccount()
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentDefaultAccessName)
            let record = try await database.record(for: recordID)
            guard generation == outbox.generation else { return }
            guard let configuration = SyncedDefaultAccessConfiguration(record: record) else { return }
            if let pending = outbox.pendingDefaultAccess,
               DefaultAccessSyncState.resolve(pending, configuration) == pending { return }
            let fingerprint = configuration.fingerprint
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
            let generation = try await outbox.verifyAccount()
            let catalogs = try await CrossDeviceApplicationCatalog.fetch(from: database)
            guard generation == outbox.generation else { return }
            let mobile = catalogs.filter { $0.platform != .macOS }
            applicationCatalog.setMobileApplications(
                CrossDeviceApplicationCatalog.mergedApplications(from: mobile)
            )
        } catch {
            logger.error("Mobile application catalog fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishApplicationCatalog() async {
        do {
            let generation = try await outbox.verifyAccount()
            let catalog = CrossDeviceApplicationCatalog(
                deviceID: CrossDeviceCatalogDevice.identifier(in: .standard), platform: .macOS,
                applications: portableCatalogApplications()
            )
            let record = try await recordForUpdate(
                type: CrossDeviceCloudRecord.applicationCatalogType,
                id: CKRecord.ID(recordName: catalog.recordName)
            )
            guard generation == outbox.generation else { return }
            catalog.write(to: record)
            _ = try await database.save(record)
        } catch {
            // Catalogs are device-local snapshots; the periodic refresh retries their latest state.
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

    private func recordForUpdate(type: String, id: CKRecord.ID) async throws -> CKRecord {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
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

}
