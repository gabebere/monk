import Foundation
import FamilyControls
import ManagedSettings
import OSLog
import SwiftData

@MainActor
final class IntentBlockManager {
    static let shared = IntentBlockManager()

    private let store = ManagedSettingsStore(named: .intentBlock)
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "IntentBlock")

    private init() {
        IntentStateStore.bootstrap()
        IntentAppIndexStore.bootstrap()
    }

    // MARK: - Authorization
    func ensureAuthorization() async -> Bool {
        let center = AuthorizationCenter.shared
        switch center.authorizationStatus {
        case .approved:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                try await center.requestAuthorization(for: .individual)
                return center.authorizationStatus == .approved
            } catch {
                logger.error("Intent authorization failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Public API

    /// Apply shields based on whether a project session is active. When a project is active, Intent Mode is ignored and only the project's allowlist (plus forced apps) remains accessible.
    func applyShields(preferences: Preferences,
                      activeProjectSelection: FamilyActivitySelection?,
                      now: Date = .now) {
        let forcedTokens = forcedAllowTokens()
        if let projectSelection = activeProjectSelection {
            applyProjectAllowlist(projectSelection, forced: forcedTokens)
            return
        }

        // Intent Mode baseline path
        guard shouldApplyBaseline(preferences: preferences, now: now) else {
            clear()
            return
        }

        let state = IntentStateStore.load()
        let activeUnlocks = (state?.activeUnlocks ?? []).filter { $0.expiresAt > now }
        var allowApps = forcedTokens
        allowApps.formUnion(decodeApplications(from: preferences.baselineAlwaysAllowedManagedSelectionData))
        allowApps.formUnion(activeUnlocks.compactMap { $0.token })
        applyAllowlist(allowedApps: allowApps)
        pruneExpiredUnlocks(activeUnlocks)
        IntentStateStore.syncFromPreferences(preferences, activeUnlocks: activeUnlocks)
    }

    func clear() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    enum UnlockResult {
        case unlocked(IntentUnlock, IntentAppIndexEntry)
        case ambiguous
        case noMatch
        case authorizationDenied
        case invalidMinutes
    }

    /// Register a temporary unlock based on a prefix query and duration (minutes).
    func registerTemporaryUnlock(query: String,
                                 minutes: Int,
                                 source: UnlockSource,
                                 modelContext: ModelContext) async -> UnlockResult {
        guard minutes >= 2, minutes <= 60 else { return .invalidMinutes }
        guard await ensureAuthorization() else { return .authorizationDenied }

        // Ensure we have an index to match against.
        let preferences: Preferences = (try? modelContext.fetch(FetchDescriptor<Preferences>()))?.first ?? Preferences(hasConvertedDailyGoal: true)
        IntentAppIndexStore.rebuild(from: preferences.baselineManagedAppsSelectionData)

        guard let entry = IntentAppIndexStore.resolve(prefix: query) else {
            // If there are multiple matches resolve() returns nil; we treat it as ambiguous when query not empty.
            return query.isEmpty ? .noMatch : .ambiguous
        }

        let durationSeconds = minutes * 60
        let unlock = IntentUnlock(applicationTokenData: entry.applicationTokenData,
                                  startedAt: Date(),
                                  durationSeconds: durationSeconds)

        var state = IntentStateStore.load() ?? IntentStateStore.defaultState()
        state.activeUnlocks = state.activeUnlocks.filter { $0.expiresAt > Date() } + [unlock]
        state.updatedAt = Date()
        IntentStateStore.save(state)

        applyShields(preferences: preferences,
                     activeProjectSelection: nil)

        // Persist analytics locally.
        let event = UnlockEvent(applicationTokenData: entry.applicationTokenData,
                                appDisplayName: entry.displayName,
                                startedAt: unlock.startedAt,
                                durationSeconds: durationSeconds,
                                source: source)
        modelContext.insert(event)
        _ = modelContext.saveOrRollback()

        return .unlocked(unlock, entry)
    }

    // MARK: - Private helpers

    private func applyProjectAllowlist(_ selection: FamilyActivitySelection, forced: Set<ManagedSettings.ApplicationToken>) {
        let allowedApps = selection.applicationTokens.union(forced)
        applyAllowlist(allowedApps: allowedApps)
    }

    private func applyAllowlist(allowedApps: Set<ManagedSettings.ApplicationToken>) {
        store.shield.applicationCategories = .all(except: allowedApps)
        store.shield.applications = nil
        store.shield.webDomains = nil
    }

    private func forcedAllowTokens() -> Set<ManagedSettings.ApplicationToken> {
        // Best-effort resolution of critical apps that should remain accessible.
        let criticalBundleIds = [
            "com.apple.MobileSMS",      // Messages
            "com.apple.mobilephone",    // Phone
            "com.apple.facetime"        // FaceTime
        ]
        let tokens = criticalBundleIds.compactMap { ManagedSettings.Application(bundleIdentifier: $0).token }
        return Set(tokens)
    }

    private func decodeApplications(from data: Data?) -> Set<ManagedSettings.ApplicationToken> {
        guard let data else { return [] }
        guard let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return [] }
        return selection.applicationTokens
    }

    private func pruneExpiredUnlocks(_ unlocks: [IntentUnlock]) {
        let valid = unlocks.filter { $0.expiresAt > Date() }
        IntentStateStore.replaceActiveUnlocks(valid)
    }

    private func shouldApplyBaseline(preferences: Preferences, now: Date) -> Bool {
        guard preferences.baselineEnabled else { return false }
        guard preferences.baselineScheduleEnabled,
              let data = preferences.baselineScheduleData,
              let schedule = try? JSONDecoder().decode(IntentSchedule.self, from: data) else {
            return true
        }
        return schedule.isActive(at: now)
    }

}

private extension ManagedSettingsStore.Name {
    static let intentBlock = ManagedSettingsStore.Name("IntentBlock")
}
