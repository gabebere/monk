import Foundation
import FamilyControls
import ManagedSettings

@MainActor
final class HardBlockManager {
    static let shared = HardBlockManager()

    private let store = ManagedSettingsStore(named: .projectHardBlock)

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

    @discardableResult
    func activateHardBlock(for project: Project) -> Bool {
        guard project.hardBlockEnabled,
              AuthorizationCenter.shared.authorizationStatus == .approved,
              let selection = decodeSelection(from: project.hardBlockSelectionData),
              hasShieldableTargets(selection) else {
            return false
        }

        SoftBlockManager.shared.suspendForHardBlock()

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
        return true
    }

    func deactivateHardBlock() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    func encodeSelection(_ selection: FamilyActivitySelection?) -> Data? {
        guard let selection else { return nil }
        return try? JSONEncoder().encode(selection)
    }

    func decodeSelection(from data: Data?) -> FamilyActivitySelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private func hasShieldableTargets(_ selection: FamilyActivitySelection) -> Bool {
        selection.includeEntireCategory ||
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }
}

private extension ManagedSettingsStore.Name {
    static let projectHardBlock = ManagedSettingsStore.Name("ProjectHardBlock")
}
