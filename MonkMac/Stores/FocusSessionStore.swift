import Combine
import Foundation

@MainActor
final class FocusSessionStore: ObservableObject {
    static let persistedPolicyKey = "com.gbr.Monk.activeFocusPolicy"
    static let defaultAllowedApplicationsKey = "com.gbr.Monk.defaultAllowedApplications"
    static let alwaysAllowedApplicationsKey = "com.gbr.Monk.alwaysAllowedApplications"
    static let defaultBlockingEnabledKey = "com.gbr.Monk.defaultBlockingEnabled"

    @Published private(set) var activePolicy: FocusPolicy?
    @Published private(set) var isAwaitingSessionDecision = false
    @Published private(set) var defaultBlockingEnabled: Bool
    @Published private(set) var alwaysAllowedApplications: [ApplicationDescriptor]
    @Published private(set) var now = Date.now
    @Published private(set) var lastBlockedApplicationName: String?
    @Published private(set) var lastBlockedWebsite: String?

    private let guardian: ApplicationGuarding
    private let websiteGuardian: WebsiteGuarding
    private let syncService: FocusPolicySyncing?
    private let calendarRecorder: FocusCalendarRecording?
    private let defaults: UserDefaults
    private let nowProvider: () -> Date
    private let installedBrowserProvider: () -> [ApplicationDescriptor]
    private var timer: Timer?
    private var didAttemptRestore = false
    var onSessionAwaitingDecision: (() -> Void)?

    init(
        guardian: ApplicationGuarding,
        websiteGuardian: WebsiteGuarding,
        syncService: FocusPolicySyncing? = nil,
        calendarRecorder: FocusCalendarRecording? = nil,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = { .now },
        installedBrowserProvider: @escaping () -> [ApplicationDescriptor] = { [] }
    ) {
        self.guardian = guardian
        self.websiteGuardian = websiteGuardian
        self.syncService = syncService
        self.calendarRecorder = calendarRecorder
        self.defaults = defaults
        self.nowProvider = nowProvider
        self.installedBrowserProvider = installedBrowserProvider
        self.now = nowProvider()
        self.defaultBlockingEnabled = defaults.bool(forKey: Self.defaultBlockingEnabledKey)
        self.alwaysAllowedApplications = Self.loadApplications(
            from: defaults,
            key: Self.alwaysAllowedApplicationsKey
        )
    }

    deinit {
        timer?.invalidate()
    }

    var remainingTime: TimeInterval {
        guard let activePolicy else { return 0 }
        return max(0, activePolicy.endsAt.timeIntervalSince(now))
    }

    var remainingTimeLabel: String {
        let totalSeconds = Int(remainingTime.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var preventsTermination: Bool {
        activePolicy != nil || defaultBlockingEnabled
    }

    func configureDefaultBlocking(
        enabled: Bool,
        alwaysAllowedApplications: [ApplicationDescriptor]
    ) {
        guard activePolicy == nil else { return }

        self.defaultBlockingEnabled = enabled
        self.alwaysAllowedApplications = alwaysAllowedApplications
        defaults.set(enabled, forKey: Self.defaultBlockingEnabledKey)
        save(alwaysAllowedApplications, forKey: Self.alwaysAllowedApplicationsKey)

        if enabled {
            guardian.beginDefaultBlocking(allowing: alwaysAllowedApplications)
        } else {
            guardian.stopEnforcing()
        }
        syncService?.publishDefaultAccess(
            enabled: enabled,
            alwaysAllowedApplications: alwaysAllowedApplications
        )
    }

    func applySyncedDefaultBlocking(
        enabled: Bool,
        alwaysAllowedApplications: [ApplicationDescriptor]
    ) {
        self.defaultBlockingEnabled = enabled
        self.alwaysAllowedApplications = alwaysAllowedApplications
        defaults.set(enabled, forKey: Self.defaultBlockingEnabledKey)
        save(alwaysAllowedApplications, forKey: Self.alwaysAllowedApplicationsKey)
        if let activePolicy {
            guardian.beginEnforcing(
                activePolicy,
                alwaysAllowing: enabled ? alwaysAllowedApplications : []
            )
        } else {
            activateDefaultBlockingIfNeeded()
        }
    }

    func start(
        intention: String,
        duration: TimeInterval,
        allowedApplications: [ApplicationDescriptor],
        allowedDomains: [String]
    ) {
        guard activePolicy == nil else { return }

        let currentDate = nowProvider()
        let effectiveApplications = applicationsIncludingBrowsers(
            allowedApplications,
            whenAllowing: allowedDomains
        )
        let policy = FocusPolicy(
            intention: intention,
            startedAt: currentDate,
            duration: duration,
            allowedApplications: effectiveApplications,
            allowedDomains: allowedDomains
        )

        didAttemptRestore = true
        saveDefaultAllowedApplications(allowedApplications)
        persist(policy)
        activate(policy, at: currentDate)
        syncService?.publish(policy)
    }

    func startSyncedFocus(
        _ commitment: SyncedFocusCommitment,
        resolvedApplications: [ApplicationDescriptor] = []
    ) {
        if commitment.isEnded {
            guard activePolicy?.id == commitment.sessionID else { return }
            completeSession()
            return
        }

        guard activePolicy == nil || activePolicy?.id == commitment.sessionID else { return }
        if let activePolicy,
           activePolicy.id == commitment.sessionID,
           commitment.endsAt <= activePolicy.endsAt.addingTimeInterval(1) {
            return
        }

        let requestedApplications: [ApplicationDescriptor]
        if commitment.allowedApplications.isEmpty {
            requestedApplications = defaultBlockingEnabled ? [] : defaultAllowedApplications()
        } else {
            requestedApplications = resolvedApplications
        }

        let policy = FocusPolicy(
            id: commitment.sessionID,
            intention: commitment.intention,
            startedAt: commitment.startedAt,
            endsAt: commitment.endsAt,
            allowedApplications: applicationsIncludingBrowsers(
                requestedApplications,
                whenAllowing: commitment.allowedDomains
            ),
            allowedDomains: commitment.allowedDomains
        )

        didAttemptRestore = true
        persist(policy)
        activate(policy, at: nowProvider())
    }

    func restorePersistedSessionIfNeeded() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true

        guard let data = defaults.data(forKey: Self.persistedPolicyKey),
              let policy = try? JSONDecoder().decode(FocusPolicy.self, from: data) else {
            defaults.removeObject(forKey: Self.persistedPolicyKey)
            activateDefaultBlockingIfNeeded()
            return
        }

        let currentDate = nowProvider()
        activate(policy, at: currentDate)
        if policy.endsAt > currentDate {
            syncService?.publish(policy)
        }
    }

    func recordBlockedApplication(named name: String) {
        lastBlockedApplicationName = name
    }

    func recordBlockedWebsite(_ website: String) {
        lastBlockedWebsite = website
    }

    func extendExpiredFocus(by duration: TimeInterval) {
        guard duration > 0,
              isAwaitingSessionDecision,
              let policy = activePolicy else {
            return
        }

        let extendedPolicy = FocusPolicy(
            id: policy.id,
            intention: policy.intention,
            startedAt: policy.startedAt,
            endsAt: nowProvider().addingTimeInterval(duration),
            allowedApplications: policy.allowedApplications,
            allowedDomains: policy.allowedDomains
        )
        persist(extendedPolicy)
        activate(extendedPolicy, at: nowProvider())
        syncService?.publish(extendedPolicy)
    }

    func endExpiredFocus() {
        guard isAwaitingSessionDecision, let policy = activePolicy else { return }
        syncService?.end(policy)
        completeSession()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = self.nowProvider()
                if self.remainingTime <= 0 {
                    self.markSessionAwaitingDecision()
                }
            }
        }
    }

    private func activate(_ policy: FocusPolicy, at currentDate: Date) {
        activePolicy = policy
        now = currentDate
        isAwaitingSessionDecision = policy.endsAt <= currentDate
        lastBlockedApplicationName = nil
        lastBlockedWebsite = nil
        guardian.beginEnforcing(
            policy,
            alwaysAllowing: defaultBlockingEnabled ? alwaysAllowedApplications : []
        )
        websiteGuardian.beginEnforcing(policy)
        if isAwaitingSessionDecision {
            timer?.invalidate()
            timer = nil
            onSessionAwaitingDecision?()
        } else {
            startTimer()
        }
    }

    private func persist(_ policy: FocusPolicy) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        defaults.set(data, forKey: Self.persistedPolicyKey)
    }

    private func saveDefaultAllowedApplications(_ applications: [ApplicationDescriptor]) {
        save(applications, forKey: Self.defaultAllowedApplicationsKey)
    }

    private func defaultAllowedApplications() -> [ApplicationDescriptor] {
        Self.loadApplications(from: defaults, key: Self.defaultAllowedApplicationsKey)
    }

    private func applicationsIncludingBrowsers(
        _ applications: [ApplicationDescriptor],
        whenAllowing domains: [String]
    ) -> [ApplicationDescriptor] {
        guard !domains.isEmpty else { return applications }

        var seen = Set(applications.map(\.id))
        var result = applications
        for browser in installedBrowserProvider() where seen.insert(browser.id).inserted {
            result.append(browser)
        }
        return result
    }

    private func completeSession() {
        let completedPolicy = activePolicy
        timer?.invalidate()
        timer = nil
        websiteGuardian.stopEnforcing()
        defaults.removeObject(forKey: Self.persistedPolicyKey)
        activePolicy = nil
        isAwaitingSessionDecision = false
        lastBlockedApplicationName = nil
        lastBlockedWebsite = nil
        if defaultBlockingEnabled {
            guardian.beginDefaultBlocking(allowing: alwaysAllowedApplications)
        } else {
            guardian.stopEnforcing()
        }
        if let completedPolicy {
            calendarRecorder?.recordCompletedFocus(completedPolicy)
        }
    }

    private func markSessionAwaitingDecision() {
        timer?.invalidate()
        timer = nil
        now = nowProvider()
        isAwaitingSessionDecision = true
        onSessionAwaitingDecision?()
    }

    private func activateDefaultBlockingIfNeeded() {
        guard defaultBlockingEnabled else {
            guardian.stopEnforcing()
            return
        }
        guardian.beginDefaultBlocking(allowing: alwaysAllowedApplications)
    }

    private func save(_ applications: [ApplicationDescriptor], forKey key: String) {
        guard let data = try? JSONEncoder().encode(applications) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadApplications(
        from defaults: UserDefaults,
        key: String
    ) -> [ApplicationDescriptor] {
        guard let data = defaults.data(forKey: key),
              let applications = try? JSONDecoder().decode([ApplicationDescriptor].self, from: data) else {
            return []
        }
        return applications
    }
}
