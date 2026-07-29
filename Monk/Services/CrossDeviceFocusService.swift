import CloudKit
import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog
import UIKit

enum FocusCommitmentStartError: LocalizedError {
    case alreadyActive
    case invalidDuration
    case permissionDenied
    case selectionEncodingFailed
    case browserSelectionRequired

    var errorDescription: String? {
        switch self {
        case .alreadyActive:
            "A focus is already active. It must finish before another can begin."
        case .invalidDuration:
            "Choose a focus duration greater than zero."
        case .permissionDenied:
            "Monk needs Screen Time access to block apps and websites."
        case .selectionEncodingFailed:
            "Monk could not securely save this app selection."
        case .browserSelectionRequired:
            "Choose at least one browser to open your allowed websites."
        }
    }
}

@MainActor
final class CrossDeviceFocusService: ObservableObject {
    static let shared = CrossDeviceFocusService()

    nonisolated static let recordType = CrossDeviceCloudRecord.focusType
    nonisolated static let subscriptionID = "monk-focus-commitments"

    private static let selectionKey = "crossDeviceFocus.allowedSelection"
    private static let selectionConfiguredKey = "crossDeviceFocus.allowedSelectionConfigured"
    private static let browserSelectionKey = "crossDeviceFocus.browserSelection"
    private static let applicationMappingsKey = "crossDeviceFocus.applicationMappings"
    private static let participationKey = "crossDeviceFocus.enforcementEnabled"

    private let container = CKContainer(identifier: "iCloud.com.gbr.Monk")
    private lazy var database = container.privateCloudDatabase
    private let settingsStore = ManagedSettingsStore(named: .crossDeviceFocus)
    private let activityCenter = DeviceActivityCenter()
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "CrossDeviceFocus")
    private let defaults = UserDefaults(suiteName: CrossDeviceFocusShared.appGroupIdentifier) ?? .standard
    private var expiryTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var installedApplications: [ManagedSettings.Application] = []
    private var didStart = false

    @Published private(set) var currentState: CrossDeviceFocusState?
    @Published private(set) var isScreenTimeAuthorized: Bool
    @Published private(set) var hasConfiguredAllowedApps: Bool
    @Published private(set) var hasConfiguredBrowserApps = false
    @Published private(set) var iCloudAvailable = false
    @Published private(set) var syncStatus = "Checking iCloud…"
    @Published private(set) var searchableApplications: [MobileInstalledApplication] = []
    @Published private(set) var isApplicationCatalogAuthorized = false
    @Published private(set) var macApplications: [CrossDeviceApplication] = []
    @Published private(set) var hasRefreshedApplicationCatalog = false

    private init() {
        isScreenTimeAuthorized = Self.screenTimeAuthorizationIsApproved
        hasConfiguredAllowedApps = defaults.bool(forKey: Self.selectionConfiguredKey)
        hasConfiguredBrowserApps = !browserSelection().applicationTokens.isEmpty
    }

    deinit {
        expiryTask?.cancel()
        pollingTask?.cancel()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    var isParticipating: Bool {
        if defaults.object(forKey: Self.participationKey) == nil {
            return true
        }
        return defaults.bool(forKey: Self.participationKey)
    }

    var activeState: CrossDeviceFocusState? {
        guard let state = currentState, state.endsAt > .now else { return nil }
        return state
    }

    var applicationCatalogCanBeRequested: Bool {
        if #available(iOS 26.4, *) {
            return true
        }
        return false
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        currentState = loadState()

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshReadiness()
                await self?.reconcile()
            }
        }

        Task {
            await refreshReadiness()
            await ensureSubscription()
            await reconcile()
        }
        startPolling()
    }

    func refreshReadiness() async {
        isScreenTimeAuthorized = Self.screenTimeAuthorizationIsApproved
        hasConfiguredAllowedApps = defaults.bool(forKey: Self.selectionConfiguredKey)
        hasConfiguredBrowserApps = !browserSelection().applicationTokens.isEmpty
        await refreshInstalledApplications()

        do {
            let status = try await container.accountStatus()
            iCloudAvailable = status == .available
            syncStatus = iCloudAvailable ? "Syncing with iCloud" : "iCloud is unavailable on this device"
            if iCloudAvailable {
                await fetchMacApplicationCatalog()
            }
        } catch {
            iCloudAvailable = false
            syncStatus = "Could not reach iCloud"
        }
    }

    func requestScreenTimeAuthorization() async -> Bool {
        if Self.screenTimeAuthorizationIsApproved {
            isScreenTimeAuthorized = true
            await refreshInstalledApplications()
            return true
        }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isScreenTimeAuthorized = Self.screenTimeAuthorizationIsApproved
            await refreshInstalledApplications()
            return isScreenTimeAuthorized
        } catch {
            isScreenTimeAuthorized = false
            logger.error("Screen Time authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func requestApplicationCatalogAuthorization() async -> Bool {
        guard #available(iOS 26.4, *) else { return false }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isScreenTimeAuthorized = Self.screenTimeAuthorizationIsApproved
            await refreshInstalledApplications()
            return isApplicationCatalogAuthorized
        } catch {
            logger.error("App search authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func displayName(for application: MobileInstalledApplication) -> String {
        let trimmedName = application.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBundleIdentifier = application.bundleIdentifier.map {
            trimmedName.caseInsensitiveCompare($0) == .orderedSame
        } ?? false
        if trimmedName.count > 1,
           trimmedName.caseInsensitiveCompare("Application") != .orderedSame,
           !isBundleIdentifier {
            return trimmedName
        }

        let resolvedName = CrossDeviceApplication.resolvedDisplayName(
            localizedDisplayName: application.displayName,
            bundleIdentifier: application.bundleIdentifier
        )
        if let bundleIdentifier = application.bundleIdentifier,
           let macApplication = macApplications.first(where: {
               $0.sourceBundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
           }) {
            return macApplication.displayName
        }

        if let bundleIdentifier = application.bundleIdentifier {
            return CrossDeviceApplication.fallbackDisplayName(for: bundleIdentifier)
        }
        return resolvedName
    }

    func completeSetup(
        with selection: FamilyActivitySelection,
        browsers: FamilyActivitySelection
    ) throws {
        guard isScreenTimeAuthorized else {
            throw FocusCommitmentStartError.permissionDenied
        }
        guard saveAllowedSelection(selection) else {
            throw FocusCommitmentStartError.selectionEncodingFailed
        }
        guard saveBrowserSelection(browsers) else {
            throw FocusCommitmentStartError.selectionEncodingFailed
        }
        defaults.set(true, forKey: Self.participationKey)
        Task { await reconcile() }
    }

    func beginFocus(
        intention: String,
        duration: TimeInterval,
        allowedSelection: FamilyActivitySelection,
        allowedBrowsers: FamilyActivitySelection,
        allowedDomains: [String],
        allowedApplications: [CrossDeviceApplication] = []
    ) async throws {
        guard activeState == nil else {
            throw FocusCommitmentStartError.alreadyActive
        }
        guard duration > 0 else {
            throw FocusCommitmentStartError.invalidDuration
        }
        guard await requestScreenTimeAuthorization() else {
            throw FocusCommitmentStartError.permissionDenied
        }
        guard let selectionData = try? JSONEncoder().encode(allowedSelection) else {
            throw FocusCommitmentStartError.selectionEncodingFailed
        }
        guard allowedDomains.isEmpty || !allowedBrowsers.applicationTokens.isEmpty else {
            throw FocusCommitmentStartError.browserSelectionRequired
        }
        guard saveBrowserSelection(allowedBrowsers) else {
            throw FocusCommitmentStartError.selectionEncodingFailed
        }

        let startedAt = Date()
        let portableApplications = mergedPortableApplications(
            localSelection: allowedSelection,
            remoteSelection: allowedApplications
        )
        let state = CrossDeviceFocusState(
            sessionID: UUID(),
            intention: intention,
            startedAt: startedAt,
            endsAt: startedAt.addingTimeInterval(duration),
            allowedDomains: allowedDomains,
            allowedApplications: portableApplications,
            allowedSelectionData: selectionData,
            sourcePlatform: "iOS"
        )

        defaults.set(selectionData, forKey: Self.selectionKey)
        defaults.set(true, forKey: Self.selectionConfiguredKey)
        defaults.set(true, forKey: Self.participationKey)
        hasConfiguredAllowedApps = true
        saveState(state)
        currentState = state
        applyState(state)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        publish(state)
    }

    func allowedSelection() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: Self.selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    func browserSelection() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: Self.browserSelectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    func unresolvedApplications(for state: CrossDeviceFocusState) -> [CrossDeviceApplication] {
        state.allowedApplications.filter { resolvedApplicationToken(for: $0) == nil }
    }

    @discardableResult
    func saveApplicationMapping(
        _ selection: FamilyActivitySelection,
        for application: CrossDeviceApplication
    ) -> Bool {
        guard !selection.applicationTokens.isEmpty,
              let selectionData = try? JSONEncoder().encode(selection) else {
            return false
        }

        var mappings = applicationMappings()
        for key in mappingKeys(for: application) {
            mappings[key] = selectionData
        }
        guard let mappingsData = try? JSONEncoder().encode(mappings) else { return false }
        defaults.set(mappingsData, forKey: Self.applicationMappingsKey)

        if let state = activeState {
            applyState(state)
            currentState = state
        }
        return true
    }

    @discardableResult
    func saveAllowedSelection(_ selection: FamilyActivitySelection) -> Bool {
        let state = activeState
        guard state == nil || !hasConfiguredAllowedApps,
              let data = try? JSONEncoder().encode(selection) else {
            return false
        }

        defaults.set(data, forKey: Self.selectionKey)
        defaults.set(true, forKey: Self.selectionConfiguredKey)
        hasConfiguredAllowedApps = true
        if let state {
            applyState(state)
        }
        return true
    }

    @discardableResult
    func saveBrowserSelection(_ selection: FamilyActivitySelection) -> Bool {
        let state = activeState
        guard state == nil || !hasConfiguredBrowserApps,
              let data = try? JSONEncoder().encode(selection) else {
            return false
        }

        defaults.set(data, forKey: Self.browserSelectionKey)
        hasConfiguredBrowserApps = !selection.applicationTokens.isEmpty
        if let state {
            applyState(state)
        }
        return true
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> Bool {
        guard isParticipating,
              let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.subscriptionID == Self.subscriptionID else {
            return false
        }

        if let queryNotification = notification as? CKQueryNotification,
           let recordID = queryNotification.recordID {
            do {
                let record = try await database.record(for: recordID)
                if let commitment = RemoteFocusCommitment(record: record) {
                    await apply(commitment)
                    return true
                }
            } catch {
                logger.error("Unable to fetch remote focus: \(error.localizedDescription, privacy: .public)")
            }
            return false
        }

        await fetchLatestCommitment()
        return true
    }

    private func reconcile() async {
        guard isParticipating else {
            clearEnforcement()
            return
        }

        currentState = loadState()
        if let state = currentState {
            if state.endsAt > .now {
                applyState(state)
                return
            }
            clearEnforcement()
        }

        await fetchLatestCommitment()
    }

    private func ensureSubscription() async {
        guard iCloudAvailable else { return }

        do {
            let subscriptions = try await database.allSubscriptions()
            if let existing = subscriptions.first(where: { $0.subscriptionID == Self.subscriptionID }) as? CKQuerySubscription,
               existing.recordType == Self.recordType,
               existing.notificationInfo?.shouldSendContentAvailable == true {
                return
            }

            if subscriptions.contains(where: { $0.subscriptionID == Self.subscriptionID }) {
                _ = try? await database.deleteSubscription(withID: Self.subscriptionID)
            }

            let subscription = CKQuerySubscription(
                recordType: Self.recordType,
                predicate: NSPredicate(value: true),
                subscriptionID: Self.subscriptionID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate]
            )
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database.save(subscription)
        } catch {
            syncStatus = "iCloud sync needs attention"
            logger.error("Unable to configure cross-device subscription: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchLatestCommitment() async {
        guard isParticipating, iCloudAvailable else { return }

        do {
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentFocusName)
            let record = try await database.record(for: recordID)
            guard let latest = RemoteFocusCommitment(record: record), latest.endsAt > .now else {
                syncStatus = "Syncing with iCloud"
                return
            }
            await apply(latest)
        } catch let error as CKError where error.code == .unknownItem {
            syncStatus = "Syncing with iCloud"
        } catch {
            syncStatus = "iCloud sync needs attention"
            logger.error("Unable to reconcile cross-device focus: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ commitment: RemoteFocusCommitment) async {
        guard commitment.endsAt > .now else { return }
        guard activeState == nil || activeState?.sessionID == commitment.sessionID else { return }

        await refreshInstalledApplications()

        let state = CrossDeviceFocusState(
            sessionID: commitment.sessionID,
            intention: commitment.intention,
            startedAt: commitment.startedAt,
            endsAt: commitment.endsAt,
            allowedDomains: commitment.allowedDomains,
            allowedApplications: commitment.allowedApplications,
            sourcePlatform: commitment.sourcePlatform
        )
        cacheAutomaticMappings(for: state.allowedApplications)
        saveState(state)
        currentState = state
        applyState(state)
    }

    private func applyState(_ state: CrossDeviceFocusState) {
        guard isParticipating, state.endsAt > .now else {
            clearEnforcement()
            return
        }

        guard isScreenTimeAuthorized else {
            syncStatus = "Open Monk once to grant Screen Time access"
            return
        }

        let sessionSelection = state.allowedSelectionData.flatMap {
            try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0)
        }
        guard !state.allowedApplications.isEmpty || sessionSelection != nil || hasConfiguredAllowedApps else {
            syncStatus = "Open Monk once to choose allowed apps"
            return
        }
        guard state.allowedDomains.isEmpty || hasConfiguredBrowserApps else {
            syncStatus = "Open Monk once to choose your browsers"
            return
        }

        var selection: FamilyActivitySelection
        if let sessionSelection {
            selection = sessionSelection
            selection.applicationTokens.formUnion(
                resolvedSelection(for: state.allowedApplications).applicationTokens
            )
        } else if !state.allowedApplications.isEmpty {
            selection = resolvedSelection(for: state.allowedApplications)
        } else {
            selection = allowedSelection()
        }
        var allowedApplicationTokens = selection.applicationTokens
        if !state.allowedDomains.isEmpty {
            allowedApplicationTokens.formUnion(browserSelection().applicationTokens)
        }
        settingsStore.shield.applications = nil
        settingsStore.shield.applicationCategories = .all(except: allowedApplicationTokens)

        let allowedDomains = Set(state.allowedDomains.prefix(50).map(WebDomain.init(domain:)))
        settingsStore.webContent.blockedByFilter = .all(except: allowedDomains)

        scheduleExpiry(for: state)
        syncStatus = "Focus synced"
        logger.notice("Enforcing focus \(state.sessionID.uuidString, privacy: .public)")
    }

    private func resolvedSelection(
        for applications: [CrossDeviceApplication]
    ) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = Set(applications.compactMap(resolvedApplicationToken))
        return selection
    }

    private func resolvedApplicationToken(
        for application: CrossDeviceApplication
    ) -> ManagedSettings.ApplicationToken? {
        if let token = mappedSelection(for: application)?.applicationTokens.first {
            return token
        }

        return automaticallyMatchedInstalledApplication(for: application)?.token
    }

    private func mappedSelection(
        for application: CrossDeviceApplication
    ) -> FamilyActivitySelection? {
        let mappings = applicationMappings()
        guard let data = mappingKeys(for: application).compactMap({ mappings[$0] }).first else {
            return nil
        }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private func mappingKeys(for application: CrossDeviceApplication) -> [String] {
        var keys = [
            application.id,
            CrossDeviceApplication.stableID(
                displayName: application.displayName,
                bundleIdentifier: nil
            )
        ]
        if let bundleIdentifier = application.sourceBundleIdentifier {
            keys.append("bundle:\(bundleIdentifier.lowercased())")
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func automaticallyMatchedInstalledApplication(
        for application: CrossDeviceApplication
    ) -> ManagedSettings.Application? {
        if let sourceBundleIdentifier = application.sourceBundleIdentifier,
           let exactMatch = installedApplications.first(where: {
               $0.bundleIdentifier?.caseInsensitiveCompare(sourceBundleIdentifier) == .orderedSame
           }) {
            return exactMatch
        }

        let nameMatches = installedApplications.filter {
            application.matches(
                displayName: installedApplicationDisplayName($0),
                bundleIdentifier: $0.bundleIdentifier
            )
        }
        return nameMatches.count == 1 ? nameMatches[0] : nil
    }

    private func installedApplicationDisplayName(
        _ application: ManagedSettings.Application
    ) -> String {
        let resolvedName = CrossDeviceApplication.resolvedDisplayName(
            localizedDisplayName: application.localizedDisplayName,
            bundleIdentifier: application.bundleIdentifier
        )
        guard let bundleIdentifier = application.bundleIdentifier,
              (application.localizedDisplayName?
                  .trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) <= 1,
              let macApplication = macApplications.first(where: {
                  $0.sourceBundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
              }) else {
            return resolvedName
        }
        return macApplication.displayName
    }

    private func cacheAutomaticMappings(for applications: [CrossDeviceApplication]) {
        var mappings = applicationMappings()
        var didChange = false

        for application in applications where mappedSelection(for: application) == nil {
            guard let token = automaticallyMatchedInstalledApplication(for: application)?.token else {
                continue
            }
            var selection = FamilyActivitySelection()
            selection.applicationTokens = [token]
            guard let data = try? JSONEncoder().encode(selection) else { continue }
            for key in mappingKeys(for: application) where mappings[key] == nil {
                mappings[key] = data
                didChange = true
            }
        }

        guard didChange,
              let data = try? JSONEncoder().encode(mappings) else { return }
        defaults.set(data, forKey: Self.applicationMappingsKey)
    }

    private func applicationMappings() -> [String: Data] {
        guard let data = defaults.data(forKey: Self.applicationMappingsKey),
              let mappings = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return mappings
    }

    private func refreshInstalledApplications() async {
        guard #available(iOS 26.4, *),
              AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess else {
            isApplicationCatalogAuthorized = false
            hasRefreshedApplicationCatalog = true
            return
        }

        isApplicationCatalogAuthorized = true
        do {
            installedApplications = try await FamilyActivityData.shared.installedApplications
            searchableApplications = installedApplications
                .compactMap { application in
                    guard let token = application.token else { return nil }
                    let displayName = installedApplicationDisplayName(application)
                    return MobileInstalledApplication(
                        token: token,
                        displayName: displayName,
                        bundleIdentifier: application.bundleIdentifier
                    )
                }
                .filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                .sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
            if let state = activeState {
                cacheAutomaticMappings(for: state.allowedApplications)
            }
        } catch {
            logger.error("Unable to resolve installed apps: \(error.localizedDescription, privacy: .public)")
        }
        hasRefreshedApplicationCatalog = true
    }

    private func mergedPortableApplications(
        localSelection: FamilyActivitySelection,
        remoteSelection: [CrossDeviceApplication]
    ) -> [CrossDeviceApplication] {
        let selectedTokens = localSelection.applicationTokens
        let localApplications = installedApplications.compactMap { application -> CrossDeviceApplication? in
            guard let token = application.token, selectedTokens.contains(token) else { return nil }
            let displayName = installedApplicationDisplayName(application)
            return CrossDeviceApplication(
                displayName: displayName,
                bundleIdentifier: application.bundleIdentifier
            )
        }

        var seen = Set<String>()
        return (localApplications + remoteSelection).filter { application in
            let key = application.sourceBundleIdentifier?.lowercased() ?? application.id
            return seen.insert(key).inserted
        }
    }

    private func fetchMacApplicationCatalog() async {
        let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.macApplicationCatalogName)
        do {
            let record = try await database.record(for: recordID)
            let ids = record["applicationIDs"] as? [String] ?? []
            let names = record["applicationNames"] as? [String] ?? []
            let bundleIdentifiers = record["applicationBundleIdentifiers"] as? [String] ?? []
            macApplications = ids.indices.compactMap { index in
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
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            if let state = activeState {
                cacheAutomaticMappings(for: state.allowedApplications)
            }
        } catch let error as CKError where error.code == .unknownItem {
            macApplications = []
        } catch {
            logger.error("Unable to fetch Mac application catalog: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var screenTimeAuthorizationIsApproved: Bool {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved, .approvedWithDataAccess:
            true
        default:
            false
        }
    }

    private func publish(_ state: CrossDeviceFocusState) {
        Task {
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentFocusName)
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: Self.recordType, recordID: recordID)
            } catch {
                syncStatus = "Focus is active here; iCloud sync failed"
                logger.error("Unable to prepare mobile focus sync: \(error.localizedDescription, privacy: .public)")
                return
            }
            record["sessionID"] = state.sessionID.uuidString as CKRecordValue
            record["intention"] = state.intention as CKRecordValue
            record["startedAt"] = state.startedAt as CKRecordValue
            record["endsAt"] = state.endsAt as CKRecordValue
            record["allowedDomains"] = state.allowedDomains as NSArray
            record["allowedApplicationIDs"] = state.allowedApplications.map(\.id) as NSArray
            record["allowedApplicationNames"] = state.allowedApplications.map(\.displayName) as NSArray
            record["allowedApplicationBundleIdentifiers"] = state.allowedApplications.map {
                $0.sourceBundleIdentifier ?? ""
            } as NSArray
            record["sourcePlatform"] = "iOS" as CKRecordValue

            do {
                _ = try await database.save(record)
                syncStatus = "Focus synced"
                logger.notice("Published mobile focus \(state.sessionID.uuidString, privacy: .public)")
            } catch {
                syncStatus = "Focus is active here; iCloud sync failed"
                logger.error("Mobile focus publish failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func scheduleExpiry(for state: CrossDeviceFocusState) {
        expiryTask?.cancel()
        let stateID = state.sessionID
        let delay = max(0, state.endsAt.timeIntervalSinceNow)
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, self?.activeState?.sessionID == stateID else { return }
            self?.clearEnforcement()
        }

        let calendar = Calendar.current
        let minimumScheduleStart = state.endsAt.addingTimeInterval(-15 * 60)
        let intervalStartDate = min(Date(), minimumScheduleStart)
        let components: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: intervalStartDate),
            intervalEnd: calendar.dateComponents(components, from: state.endsAt),
            repeats: false
        )

        do {
            try activityCenter.startMonitoring(.crossDeviceFocusExpiry, during: schedule)
        } catch {
            logger.error("Unable to schedule shield expiry: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            var catalogPollCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                catalogPollCount += 1
                if catalogPollCount >= 6 {
                    catalogPollCount = 0
                    await self.fetchMacApplicationCatalog()
                }
                await self.reconcile()
            }
        }
    }

    private func clearEnforcement() {
        expiryTask?.cancel()
        expiryTask = nil
        settingsStore.clearAllSettings()
        activityCenter.stopMonitoring([.crossDeviceFocusExpiry])
        if let url = CrossDeviceFocusShared.stateURL() {
            try? FileManager.default.removeItem(at: url)
        }
        currentState = nil
    }

    private func saveState(_ state: CrossDeviceFocusState) {
        guard let url = CrossDeviceFocusShared.stateURL(),
              let data = try? JSONEncoder().encode(state) else {
            return
        }
        try? data.write(to: url, options: [.atomic])
    }

    private func loadState() -> CrossDeviceFocusState? {
        guard let url = CrossDeviceFocusShared.stateURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CrossDeviceFocusState.self, from: data)
    }
}

private struct RemoteFocusCommitment {
    let sessionID: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let allowedDomains: [String]
    let allowedApplications: [CrossDeviceApplication]
    let sourcePlatform: String?

    init?(record: CKRecord) {
        guard record.recordType == CrossDeviceFocusService.recordType,
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
        sourcePlatform = record["sourcePlatform"] as? String
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

private extension ManagedSettingsStore.Name {
    static let crossDeviceFocus = ManagedSettingsStore.Name(CrossDeviceFocusShared.managedSettingsStoreName)
}

private extension DeviceActivityName {
    static let crossDeviceFocusExpiry = DeviceActivityName(CrossDeviceFocusShared.deviceActivityName)
}
