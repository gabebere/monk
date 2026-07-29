import Combine
import Foundation

@MainActor
final class FocusSessionStore: ObservableObject {
    static let persistedPolicyKey = "com.gbr.Monk.activeFocusPolicy"
    static let defaultAllowedApplicationsKey = "com.gbr.Monk.defaultAllowedApplications"

    @Published private(set) var activePolicy: FocusPolicy?
    @Published private(set) var now = Date.now
    @Published private(set) var lastBlockedApplicationName: String?
    @Published private(set) var lastBlockedWebsite: String?

    private let guardian: ApplicationGuarding
    private let websiteGuardian: WebsiteGuarding
    private let syncService: FocusPolicySyncing?
    private let defaults: UserDefaults
    private let nowProvider: () -> Date
    private let installedBrowserProvider: () -> [ApplicationDescriptor]
    private var timer: Timer?
    private var didAttemptRestore = false

    init(
        guardian: ApplicationGuarding,
        websiteGuardian: WebsiteGuarding,
        syncService: FocusPolicySyncing? = nil,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = { .now },
        installedBrowserProvider: @escaping () -> [ApplicationDescriptor] = { [] }
    ) {
        self.guardian = guardian
        self.websiteGuardian = websiteGuardian
        self.syncService = syncService
        self.defaults = defaults
        self.nowProvider = nowProvider
        self.installedBrowserProvider = installedBrowserProvider
        self.now = nowProvider()
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
        activePolicy != nil
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
        guard activePolicy == nil, commitment.endsAt > nowProvider() else { return }

        let requestedApplications = commitment.allowedApplications.isEmpty
            ? defaultAllowedApplications()
            : resolvedApplications

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
            return
        }

        let currentDate = nowProvider()
        guard policy.endsAt > currentDate else {
            defaults.removeObject(forKey: Self.persistedPolicyKey)
            return
        }

        activate(policy, at: currentDate)
        syncService?.publish(policy)
    }

    func recordBlockedApplication(named name: String) {
        lastBlockedApplicationName = name
    }

    func recordBlockedWebsite(_ website: String) {
        lastBlockedWebsite = website
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = self.nowProvider()
                if self.remainingTime <= 0 {
                    self.completeSession()
                }
            }
        }
    }

    private func activate(_ policy: FocusPolicy, at currentDate: Date) {
        activePolicy = policy
        now = currentDate
        lastBlockedApplicationName = nil
        lastBlockedWebsite = nil
        guardian.beginEnforcing(policy)
        websiteGuardian.beginEnforcing(policy)
        startTimer()
    }

    private func persist(_ policy: FocusPolicy) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        defaults.set(data, forKey: Self.persistedPolicyKey)
    }

    private func saveDefaultAllowedApplications(_ applications: [ApplicationDescriptor]) {
        guard let data = try? JSONEncoder().encode(applications) else { return }
        defaults.set(data, forKey: Self.defaultAllowedApplicationsKey)
    }

    private func defaultAllowedApplications() -> [ApplicationDescriptor] {
        guard let data = defaults.data(forKey: Self.defaultAllowedApplicationsKey),
              let applications = try? JSONDecoder().decode([ApplicationDescriptor].self, from: data) else {
            return []
        }
        return applications
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
        timer?.invalidate()
        timer = nil
        guardian.stopEnforcing()
        websiteGuardian.stopEnforcing()
        defaults.removeObject(forKey: Self.persistedPolicyKey)
        activePolicy = nil
        lastBlockedApplicationName = nil
        lastBlockedWebsite = nil
    }
}
