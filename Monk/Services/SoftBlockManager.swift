import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

@MainActor
final class SoftBlockManager {
    static let shared = SoftBlockManager()

    private let store = ManagedSettingsStore()

    private init() {}

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
                return false
            }
        @unknown default:
            return false
        }
    }

    func apply(selection: FamilyActivitySelection?, enabled: Bool) {
        SoftBlockUnlockStore.clearExpired()

        let hasTokens: Bool = {
            guard let selection else { return false }
            if selection.includeEntireCategory { return true }
            return !(selection.applicationTokens.isEmpty &&
                     selection.categoryTokens.isEmpty &&
                     selection.webDomainTokens.isEmpty)
        }()

        guard enabled, let selection, hasTokens else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            clearTemporaryUnlocks()
            return
        }

        if !enabled {
            clearTemporaryUnlocks()
        }

        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            clearTemporaryUnlocks()
            return
        }

        let categoryPolicy: ShieldSettings.ActivityCategoryPolicy<ManagedSettings.Application>?
        if selection.includeEntireCategory {
            let exceptions = selection.applicationTokens
            store.shield.applications = nil
            categoryPolicy = exceptions.isEmpty ? .all() : .all(except: exceptions)
        } else {
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            categoryPolicy = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        }

        store.shield.applicationCategories = categoryPolicy
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    func encodeSelection(_ selection: FamilyActivitySelection?) -> Data? {
        guard let selection else { return nil }
        return try? JSONEncoder().encode(selection)
    }

    func decodeSelection(from data: Data?) -> FamilyActivitySelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    func suspendForHardBlock() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        clearTemporaryUnlocks()
    }

    func clearTemporaryUnlocks() {
        let center = DeviceActivityCenter()
        center.stopMonitoring()
        SoftBlockUnlockStore.removeAll()
    }
}
