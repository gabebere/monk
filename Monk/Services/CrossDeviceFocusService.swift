import CloudKit
import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog
import UIKit

@MainActor
final class CrossDeviceFocusService: ObservableObject {
    static let shared = CrossDeviceFocusService()

    nonisolated static let recordType = CrossDeviceCloudRecord.focusType
    nonisolated static let subscriptionID = "monk-focus-commitments"

    private static let selectionKey = CrossDeviceFocusShared.alwaysAllowedSelectionKey
    private static let selectionConfiguredKey = "crossDeviceFocus.allowedSelectionConfigured"
    private static let browserSelectionKey = "crossDeviceFocus.browserSelection"
    private static let applicationMappingsKey = "crossDeviceFocus.applicationMappings"
    private static let participationKey = "crossDeviceFocus.enforcementEnabled"
    private static let lastEndedSessionKey = "crossDeviceFocus.lastEndedSessionID"

    private let container = CKContainer(identifier: MonkConfiguration.cloudKitContainerIdentifier)
    private lazy var database = container.privateCloudDatabase
    private let settingsStore = ManagedSettingsStore(named: .crossDeviceFocus)
    private let activityCenter = DeviceActivityCenter()
    private let logger = Logger(
        subsystem: MonkConfiguration.loggingSubsystem,
        category: "CrossDeviceFocus"
    )
    private let defaults = UserDefaults(suiteName: CrossDeviceFocusShared.appGroupIdentifier) ?? .standard
    private var expiryTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var installedApplications: [ManagedSettings.Application] = []
    private var didStart = false
    private var lastDefaultAccessFingerprint: String?

    @Published private(set) var currentState: CrossDeviceFocusState?
    @Published private(set) var isScreenTimeAuthorized: Bool
    @Published private(set) var hasConfiguredAllowedApps: Bool
    @Published private(set) var defaultBlockingEnabled: Bool
    @Published private(set) var hasConfiguredBrowserApps = false
    @Published private(set) var iCloudAvailable = false
    @Published private(set) var syncStatus = "Checking iCloud…"
    @Published private(set) var searchableApplications: [MobileInstalledApplication] = []
    @Published private(set) var isApplicationCatalogAuthorized = false
    @Published private(set) var macApplications: [CrossDeviceApplication] = []
    @Published private(set) var hasRefreshedApplicationCatalog = false
    @Published private(set) var temporaryApplicationGrants: [TemporaryApplicationGrant]

    private init() {
        isScreenTimeAuthorized = Self.screenTimeAuthorizationIsApproved
        hasConfiguredAllowedApps = defaults.bool(forKey: Self.selectionConfiguredKey)
        defaultBlockingEnabled = defaults.bool(forKey: CrossDeviceFocusShared.defaultBlockingEnabledKey)
        temporaryApplicationGrants = TemporaryApplicationGrantStore.activeGrants(from: defaults)
        hasConfiguredBrowserApps = !browserSelection().applicationTokens.isEmpty
    }

    // MARK: - Readiness and authorization

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
        currentState
    }

    var isAwaitingSessionDecision: Bool {
        guard let currentState else { return false }
        return currentState.endsAt <= .now
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
        temporaryApplicationGrants = TemporaryApplicationGrantStore.activeGrants(from: defaults)
        temporaryApplicationGrants.forEach(scheduleTemporaryGrantExpiry)

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
        defaultBlockingEnabled = defaults.bool(forKey: CrossDeviceFocusShared.defaultBlockingEnabledKey)
        hasConfiguredBrowserApps = !browserSelection().applicationTokens.isEmpty
        await refreshInstalledApplications()

        do {
            let status = try await container.accountStatus()
            iCloudAvailable = status == .available
            syncStatus = iCloudAvailable ? "Syncing with iCloud" : "iCloud is unavailable on this device"
            if iCloudAvailable {
                await fetchMacApplicationCatalog()
                await publishMobileApplicationCatalog()
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
        browsers: FamilyActivitySelection,
        defaultBlockingEnabled: Bool
    ) throws {
        guard currentState == nil else {
            throw FocusCommitmentStartError.alreadyActive
        }
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
        defaults.set(
            defaultBlockingEnabled,
            forKey: CrossDeviceFocusShared.defaultBlockingEnabledKey
        )
        self.defaultBlockingEnabled = defaultBlockingEnabled
        publishDefaultAccessConfiguration(
            selection: selection,
            enabled: defaultBlockingEnabled
        )
        Task { await reconcile() }
    }

    // MARK: - Focus lifecycle

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

    // MARK: - Temporary app access

    func temporaryUnlockApplications() async -> [MobileInstalledApplication] {
        await refreshInstalledApplications()
        return searchableApplications
    }

    nonisolated static func temporaryUnlockIdentifier(
        for application: MobileInstalledApplication
    ) -> String {
        if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier.lowercased())"
        }
        return "name:\(normalizedTemporaryUnlockName(application.displayName))"
    }

    nonisolated private static func normalizedTemporaryUnlockName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    func grantTemporaryAccess(
        to applicationIdentifier: String,
        for duration: TimeInterval
    ) async throws -> TemporaryApplicationGrantOutcome {
        guard let outcome = try await grantTemporaryAccess(
            to: [applicationIdentifier],
            for: duration
        ).first else {
            throw TemporaryApplicationGrantError.noApplications
        }
        return outcome
    }

    func grantTemporaryAccess(
        to applicationIdentifiers: [String],
        for duration: TimeInterval
    ) async throws -> [TemporaryApplicationGrantOutcome] {
        guard duration.isFinite,
              duration >= 60,
              duration <= 365 * 24 * 60 * 60 else {
            throw TemporaryApplicationGrantError.invalidDuration
        }
        var seenIdentifiers = Set<String>()
        let uniqueIdentifiers = applicationIdentifiers.filter {
            seenIdentifiers.insert($0).inserted
        }
        guard !uniqueIdentifiers.isEmpty else {
            throw TemporaryApplicationGrantError.noApplications
        }
        guard Self.screenTimeAuthorizationIsApproved else {
            throw TemporaryApplicationGrantError.screenTimePermissionRequired
        }

        await refreshInstalledApplications()
        guard isApplicationCatalogAuthorized else {
            throw TemporaryApplicationGrantError.applicationCatalogPermissionRequired
        }
        let applicationsByIdentifier = Dictionary(
            searchableApplications.map {
                (Self.temporaryUnlockIdentifier(for: $0), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let applications = uniqueIdentifiers.compactMap { applicationsByIdentifier[$0] }
        guard applications.count == uniqueIdentifiers.count else {
            throw TemporaryApplicationGrantError.applicationNotFound
        }

        currentState = loadState()
        if let currentState {
            applyState(currentState)
        } else {
            applyDefaultBlocking()
        }
        guard defaults.bool(forKey: TemporaryApplicationGrantStore.applicationShieldIsActiveKey) else {
            throw TemporaryApplicationGrantError.monkIsNotBlocking
        }

        let baseTokens = TemporaryApplicationGrantStore.baseAllowedTokens(from: defaults)
        let now = Date()
        var grants = TemporaryApplicationGrantStore.activeGrants(from: defaults, at: now)
        let existingGrantTokens = Set(grants.map(\.applicationToken))
        let newGrantCount = applications.filter {
            !baseTokens.contains($0.token) && !existingGrantTokens.contains($0.token)
        }.count
        guard grants.count + newGrantCount
                <= TemporaryApplicationGrantStore.maximumConcurrentGrants else {
            throw TemporaryApplicationGrantError.tooManyConcurrentGrants
        }

        var outcomes: [TemporaryApplicationGrantOutcome] = []
        var changedGrants: [TemporaryApplicationGrant] = []
        for application in applications {
            if baseTokens.contains(application.token) {
                outcomes.append(
                    TemporaryApplicationGrantOutcome(
                        displayName: application.displayName,
                        expiresAt: nil,
                        wasAlreadyAllowed: true
                    )
                )
                continue
            }

            let savedGrant: TemporaryApplicationGrant
            if let index = grants.firstIndex(where: {
                $0.applicationToken == application.token
            }) {
                let extensionStart = max(now, grants[index].expiresAt)
                grants[index].expiresAt = extensionStart.addingTimeInterval(duration)
                savedGrant = grants[index]
            } else {
                let grant = TemporaryApplicationGrant(
                    id: UUID(),
                    applicationIdentifier: Self.temporaryUnlockIdentifier(for: application),
                    displayName: application.displayName,
                    applicationToken: application.token,
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(duration)
                )
                grants.append(grant)
                savedGrant = grant
            }
            changedGrants.append(savedGrant)
            outcomes.append(
                TemporaryApplicationGrantOutcome(
                    displayName: application.displayName,
                    expiresAt: savedGrant.expiresAt,
                    wasAlreadyAllowed: false
                )
            )
        }

        grants.sort { $0.expiresAt < $1.expiresAt }
        TemporaryApplicationGrantStore.save(grants, to: defaults)
        temporaryApplicationGrants = grants
        applyApplicationShield(baseAllowedTokens: baseTokens)
        for grant in changedGrants {
            scheduleTemporaryGrantExpiry(grant)
        }
        let grantedNames = outcomes
            .filter { !$0.wasAlreadyAllowed }
            .map(\.displayName)
            .joined(separator: ", ")
        logger.notice(
            "Temporarily allowed \(grantedNames, privacy: .public) for \(Int(duration), privacy: .public) seconds"
        )
        return outcomes
    }

    func unresolvedApplications(for state: CrossDeviceFocusState) -> [CrossDeviceApplication] {
        state.allowedApplications.filter { resolvedApplicationToken(for: $0) == nil }
    }

    // MARK: - Expired-session decisions

    func extendExpiredFocus(by duration: TimeInterval) {
        guard duration > 0,
              let state = currentState,
              state.endsAt <= .now else {
            return
        }

        let extendedState = CrossDeviceFocusState(
            sessionID: state.sessionID,
            intention: state.intention,
            startedAt: state.startedAt,
            endsAt: Date().addingTimeInterval(duration),
            allowedDomains: state.allowedDomains,
            allowedApplications: state.allowedApplications,
            allowedSelectionData: state.allowedSelectionData,
            sourcePlatform: state.sourcePlatform
        )
        saveState(extendedState)
        currentState = extendedState
        applyState(extendedState)
        publish(extendedState)
        logger.notice("Extended focus \(state.sessionID.uuidString, privacy: .public) by \(Int(duration), privacy: .public) seconds")
    }

    func endExpiredFocus() {
        guard let state = currentState, state.endsAt <= .now else { return }
        defaults.set(state.sessionID.uuidString, forKey: Self.lastEndedSessionKey)
        publishEndedSession(state)
        completeFocusAndRestoreDefault()
        logger.notice("Ended completed focus \(state.sessionID.uuidString, privacy: .public)")
    }

    @discardableResult
    func saveAllowedSelection(_ selection: FamilyActivitySelection) -> Bool {
        let state = currentState
        guard state == nil || !hasConfiguredAllowedApps,
              let data = try? JSONEncoder().encode(selection) else {
            return false
        }

        defaults.set(data, forKey: Self.selectionKey)
        defaults.set(true, forKey: Self.selectionConfiguredKey)
        hasConfiguredAllowedApps = true
        if let state {
            applyState(state)
        } else if defaultBlockingEnabled {
            applyDefaultBlocking()
        }
        return true
    }

    @discardableResult
    func saveBrowserSelection(_ selection: FamilyActivitySelection) -> Bool {
        let state = currentState
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

    // MARK: - CloudKit reconciliation

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
            clearAllEnforcement()
            return
        }

        currentState = loadState()
        if let state = currentState {
            applyState(state)
        } else {
            applyDefaultBlocking()
        }

        await fetchDefaultAccessConfiguration()
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
            guard let latest = RemoteFocusCommitment(record: record) else {
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
        if commitment.isEnded {
            defaults.set(commitment.sessionID.uuidString, forKey: Self.lastEndedSessionKey)
            if currentState?.sessionID == commitment.sessionID {
                completeFocusAndRestoreDefault()
                logger.notice("Applied remote end for focus \(commitment.sessionID.uuidString, privacy: .public)")
            }
            return
        }

        guard defaults.string(forKey: Self.lastEndedSessionKey) != commitment.sessionID.uuidString,
              currentState == nil || currentState?.sessionID == commitment.sessionID else {
            return
        }
        if let currentState,
           currentState.sessionID == commitment.sessionID,
           commitment.endsAt <= currentState.endsAt.addingTimeInterval(1) {
            return
        }

        await refreshInstalledApplications()
        let localSelectionData = currentState?.sessionID == commitment.sessionID
            ? currentState?.allowedSelectionData
            : nil

        let state = CrossDeviceFocusState(
            sessionID: commitment.sessionID,
            intention: commitment.intention,
            startedAt: commitment.startedAt,
            endsAt: commitment.endsAt,
            allowedDomains: commitment.allowedDomains,
            allowedApplications: commitment.allowedApplications,
            allowedSelectionData: localSelectionData,
            sourcePlatform: commitment.sourcePlatform
        )
        cacheAutomaticMappings(for: state.allowedApplications)
        saveState(state)
        currentState = state
        applyState(state)
        let unresolvedCount = unresolvedApplications(for: state).count
        logger.notice(
            "Applied focus \(state.sessionID.uuidString, privacy: .public); requested apps: \(state.allowedApplications.count, privacy: .public), unmatched on this device: \(unresolvedCount, privacy: .public)"
        )
    }

    private func applyState(_ state: CrossDeviceFocusState) {
        guard isParticipating else {
            clearAllEnforcement()
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
        if defaultBlockingEnabled {
            allowedApplicationTokens.formUnion(allowedSelection().applicationTokens)
        }
        if !state.allowedDomains.isEmpty {
            allowedApplicationTokens.formUnion(browserSelection().applicationTokens)
        }
        applyApplicationShield(baseAllowedTokens: allowedApplicationTokens)

        let maximumManagedDomains = 50
        let selectedDomainLimit = max(
            0,
            maximumManagedDomains - WebsiteAccessCompanions.authenticationDomains.count
        )
        let expandedDomains = WebsiteAccessCompanions.expandedDomains(
            Array(state.allowedDomains.prefix(selectedDomainLimit))
        )
        let allowedDomains = Set(expandedDomains.map(WebDomain.init(domain:)))
        settingsStore.webContent.blockedByFilter = .all(except: allowedDomains)

        if state.endsAt > .now {
            scheduleExpiry(for: state)
            syncStatus = "Focus synced"
        } else {
            expiryTask?.cancel()
            expiryTask = nil
            activityCenter.stopMonitoring([.crossDeviceFocusExpiry])
            syncStatus = "Choose whether to extend or end"
        }
        logger.notice(
            "Enforcing focus \(state.sessionID.uuidString, privacy: .public) with \(allowedApplicationTokens.count, privacy: .public) allowed app tokens; awaiting decision: \(state.endsAt <= .now, privacy: .public)"
        )
    }

    // MARK: - Application resolution

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

    // MARK: - Cross-device catalogs and defaults

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

    private func publishMobileApplicationCatalog() async {
        guard iCloudAvailable, isApplicationCatalogAuthorized else { return }

        let applications = searchableApplications.prefix(500).map { application in
            CrossDeviceApplication(
                displayName: displayName(for: application),
                bundleIdentifier: application.bundleIdentifier
            )
        }
        let recordName = UIDevice.current.userInterfaceIdiom == .pad
            ? CrossDeviceCloudRecord.iPadApplicationCatalogName
            : CrossDeviceCloudRecord.iPhoneApplicationCatalogName
        let recordID = CKRecord.ID(recordName: recordName)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(
                recordType: CrossDeviceCloudRecord.applicationCatalogType,
                recordID: recordID
            )
        } catch {
            logger.error("Unable to prepare mobile application catalog: \(error.localizedDescription, privacy: .public)")
            return
        }

        record["platform"] = (UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS") as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        record["applicationIDs"] = applications.map(\.id) as NSArray
        record["applicationNames"] = applications.map(\.displayName) as NSArray
        record["applicationBundleIdentifiers"] = applications.map {
            $0.sourceBundleIdentifier ?? ""
        } as NSArray
        do {
            _ = try await database.save(record)
            logger.notice("Published \(applications.count, privacy: .public) mobile applications to the private catalog")
        } catch {
            logger.error("Mobile application catalog publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishDefaultAccessConfiguration(
        selection: FamilyActivitySelection,
        enabled: Bool
    ) {
        let applications = mergedPortableApplications(
            localSelection: selection,
            remoteSelection: []
        )
        let updatedAt = Date()
        lastDefaultAccessFingerprint = Self.defaultAccessFingerprint(
            enabled: enabled,
            applications: applications,
            updatedAt: updatedAt
        )

        Task {
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentDefaultAccessName)
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(
                    recordType: CrossDeviceCloudRecord.defaultAccessType,
                    recordID: recordID
                )
            } catch {
                logger.error("Unable to prepare default access sync: \(error.localizedDescription, privacy: .public)")
                return
            }

            record["enabled"] = NSNumber(value: enabled)
            record["updatedAt"] = updatedAt as CKRecordValue
            record["applicationIDs"] = applications.map(\.id) as NSArray
            record["applicationNames"] = applications.map(\.displayName) as NSArray
            record["applicationBundleIdentifiers"] = applications.map {
                $0.sourceBundleIdentifier ?? ""
            } as NSArray
            record["sourcePlatform"] = "iOS" as CKRecordValue
            do {
                _ = try await database.save(record)
                logger.notice("Published default access with \(applications.count, privacy: .public) allowed apps")
            } catch {
                logger.error("Default access sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func fetchDefaultAccessConfiguration() async {
        guard iCloudAvailable else { return }
        do {
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentDefaultAccessName)
            let record = try await database.record(for: recordID)
            guard let configuration = RemoteDefaultAccessConfiguration(record: record) else { return }
            let fingerprint = Self.defaultAccessFingerprint(
                enabled: configuration.enabled,
                applications: configuration.applications,
                updatedAt: configuration.updatedAt
            )
            guard fingerprint != lastDefaultAccessFingerprint else { return }
            lastDefaultAccessFingerprint = fingerprint

            await refreshInstalledApplications()
            cacheAutomaticMappings(for: configuration.applications)
            var selection = FamilyActivitySelection()
            selection.applicationTokens = Set(
                configuration.applications.compactMap(resolvedApplicationToken)
            )
            guard let selectionData = try? JSONEncoder().encode(selection) else { return }
            defaults.set(selectionData, forKey: Self.selectionKey)
            defaults.set(true, forKey: Self.selectionConfiguredKey)
            defaults.set(
                configuration.enabled,
                forKey: CrossDeviceFocusShared.defaultBlockingEnabledKey
            )
            hasConfiguredAllowedApps = true
            defaultBlockingEnabled = configuration.enabled
            if let currentState {
                applyState(currentState)
            } else {
                applyDefaultBlocking()
            }
            let unmatchedCount = configuration.applications.count - selection.applicationTokens.count
            logger.notice(
                "Applied default access with \(selection.applicationTokens.count, privacy: .public) local matches and \(unmatchedCount, privacy: .public) apps absent from this device"
            )
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            logger.error("Unable to fetch default access: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultAccessFingerprint(
        enabled: Bool,
        applications: [CrossDeviceApplication],
        updatedAt: Date
    ) -> String {
        let applicationIDs = applications.map(\.id).sorted().joined(separator: ",")
        return "\(enabled)|\(Int(updatedAt.timeIntervalSince1970.rounded()))|\(applicationIDs)"
    }

    private static var screenTimeAuthorizationIsApproved: Bool {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved, .approvedWithDataAccess:
            true
        default:
            false
        }
    }

    // MARK: - Cloud publishing

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
            record["sessionStatus"] = "active" as CKRecordValue

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

    private func publishEndedSession(_ state: CrossDeviceFocusState) {
        Task {
            let recordID = CKRecord.ID(recordName: CrossDeviceCloudRecord.currentFocusName)
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: Self.recordType, recordID: recordID)
            } catch {
                logger.error("Unable to prepare focus end sync: \(error.localizedDescription, privacy: .public)")
                return
            }

            record["sessionID"] = state.sessionID.uuidString as CKRecordValue
            record["intention"] = state.intention as CKRecordValue
            record["startedAt"] = state.startedAt as CKRecordValue
            record["endsAt"] = state.endsAt as CKRecordValue
            record["sessionStatus"] = "ended" as CKRecordValue
            record["sourcePlatform"] = "iOS" as CKRecordValue
            do {
                _ = try await database.save(record)
            } catch {
                logger.error("Focus end sync failed: \(error.localizedDescription, privacy: .public)")
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
            self?.currentState = state
            self?.syncStatus = "Choose whether to extend or end"
            self?.logger.notice("Focus \(stateID.uuidString, privacy: .public) reached zero; enforcement remains active")
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

    // MARK: - Enforcement and persistence

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

    private func completeFocusAndRestoreDefault() {
        expiryTask?.cancel()
        expiryTask = nil
        activityCenter.stopMonitoring([.crossDeviceFocusExpiry])
        if let url = CrossDeviceFocusShared.stateURL() {
            try? FileManager.default.removeItem(at: url)
        }
        currentState = nil
        applyDefaultBlocking()
    }

    private func applyDefaultBlocking() {
        settingsStore.clearAllSettings()
        guard isParticipating,
              defaultBlockingEnabled,
              isScreenTimeAuthorized else {
            clearTemporaryApplicationGrants()
            return
        }

        applyApplicationShield(baseAllowedTokens: allowedSelection().applicationTokens)
        syncStatus = "Default blocking is active"
    }

    private func clearAllEnforcement() {
        expiryTask?.cancel()
        expiryTask = nil
        settingsStore.clearAllSettings()
        activityCenter.stopMonitoring([.crossDeviceFocusExpiry])
        clearTemporaryApplicationGrants()
        if let url = CrossDeviceFocusShared.stateURL() {
            try? FileManager.default.removeItem(at: url)
        }
        currentState = nil
    }

    private func applyApplicationShield(
        baseAllowedTokens: Set<ManagedSettings.ApplicationToken>
    ) {
        let grants = TemporaryApplicationGrantStore.activeGrants(from: defaults)
        TemporaryApplicationGrantStore.save(grants, to: defaults)
        TemporaryApplicationGrantStore.saveBaseAllowedTokens(baseAllowedTokens, to: defaults)
        temporaryApplicationGrants = grants

        let allowedTokens = TemporaryApplicationGrantStore.combinedAllowedTokens(
            baseTokens: baseAllowedTokens,
            grants: grants
        )
        settingsStore.shield.applications = nil
        settingsStore.shield.applicationCategories = .all(except: allowedTokens)
    }

    private func scheduleTemporaryGrantExpiry(_ grant: TemporaryApplicationGrant) {
        let activityName = DeviceActivityName(TemporaryApplicationGrantStore.activityName(for: grant))
        activityCenter.stopMonitoring([activityName])

        let calendar = Calendar.current
        let intervalStartDate = min(Date(), grant.expiresAt.addingTimeInterval(-15 * 60))
        let components: Set<Calendar.Component> = [
            .era, .year, .month, .day, .hour, .minute, .second
        ]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: intervalStartDate),
            intervalEnd: calendar.dateComponents(components, from: grant.expiresAt),
            repeats: false
        )

        do {
            try activityCenter.startMonitoring(activityName, during: schedule)
        } catch {
            logger.error(
                "Unable to schedule temporary grant expiry: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func clearTemporaryApplicationGrants() {
        let grants = TemporaryApplicationGrantStore.activeGrants(from: defaults, at: .distantPast)
        activityCenter.stopMonitoring(grants.map {
            DeviceActivityName(TemporaryApplicationGrantStore.activityName(for: $0))
        })
        TemporaryApplicationGrantStore.clear(defaults)
        temporaryApplicationGrants = []
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

private extension ManagedSettingsStore.Name {
    static let crossDeviceFocus = ManagedSettingsStore.Name(CrossDeviceFocusShared.managedSettingsStoreName)
}

private extension DeviceActivityName {
    static let crossDeviceFocusExpiry = DeviceActivityName(CrossDeviceFocusShared.deviceActivityName)
}
