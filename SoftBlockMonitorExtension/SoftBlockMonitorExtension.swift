import DeviceActivity
import FamilyControls
import ManagedSettings
import OSLog

final class SoftBlockMonitorExtension: DeviceActivityMonitor {
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "SoftBlockMonitor")
    private let store = ManagedSettingsStore()

    override init() {
        SoftBlockUnlockStore.bootstrap()
        super.init()
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        Task { @MainActor in
            guard let record = SoftBlockUnlockStore.record(for: activity) else {
                logger.error("No unlock record found when interval started for \(activity.rawValue)")
                return
            }

            guard let selection = record.selection() else {
                logger.error("Unable to decode selection for unlock record \(record.id.uuidString)")
                SoftBlockUnlockStore.remove(id: record.id)
                return
            }

            applyUnlock(for: selection)
            logger.info("Applied temporary unlock for record \(record.id.uuidString)")
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        Task { @MainActor in
            guard let record = SoftBlockUnlockStore.record(for: activity) else {
                logger.error("No unlock record found when interval ended for \(activity.rawValue)")
                return
            }

            guard let selection = record.selection() else {
                logger.error("Unable to decode selection for unlock record \(record.id.uuidString) during relock")
                SoftBlockUnlockStore.remove(id: record.id)
                return
            }

            reapplyShield(for: selection)
            SoftBlockUnlockStore.remove(id: record.id)
            DeviceActivityCenter().stopMonitoring([activity])
            logger.info("Reapplied shield for record \(record.id.uuidString)")
        }
    }

    @MainActor
    private func applyUnlock(for selection: FamilyActivitySelection) {
        var blockedApps = self.store.shield.applications ?? []
        blockedApps.subtract(selection.applicationTokens)
        self.store.shield.applications = blockedApps.isEmpty ? nil : blockedApps

        if let policy = self.store.shield.applicationCategories {
            self.store.shield.applicationCategories = updatedPolicy(policy, removing: selection.applicationTokens)
        }

        var blockedWeb = self.store.shield.webDomains ?? []
        blockedWeb.subtract(selection.webDomainTokens)
        self.store.shield.webDomains = blockedWeb.isEmpty ? nil : blockedWeb
    }

    @MainActor
    private func reapplyShield(for selection: FamilyActivitySelection) {
        var blockedApps = self.store.shield.applications ?? []
        blockedApps.formUnion(selection.applicationTokens)
        self.store.shield.applications = blockedApps

        if let policy = self.store.shield.applicationCategories {
            self.store.shield.applicationCategories = updatedPolicy(policy, addingBack: selection.applicationTokens)
        }

        var blockedWeb = self.store.shield.webDomains ?? []
        blockedWeb.formUnion(selection.webDomainTokens)
        self.store.shield.webDomains = blockedWeb
    }

    private func updatedPolicy(_ policy: ShieldSettings.ActivityCategoryPolicy<ManagedSettings.Application>, removing tokens: Set<ManagedSettings.ApplicationToken>) -> ShieldSettings.ActivityCategoryPolicy<ManagedSettings.Application> {
        switch policy {
        case .none:
            return .none
        case .all(except: let exceptions):
            var updated = exceptions
            updated.formUnion(tokens)
            return updated.isEmpty ? .all() : .all(except: updated)
        case .specific(let categories, except: let exceptions):
            var updated = exceptions
            updated.formUnion(tokens)
            return updated.isEmpty ? .specific(categories) : .specific(categories, except: updated)
        @unknown default:
            return policy
        }
    }

    private func updatedPolicy(_ policy: ShieldSettings.ActivityCategoryPolicy<ManagedSettings.Application>, addingBack tokens: Set<ManagedSettings.ApplicationToken>) -> ShieldSettings.ActivityCategoryPolicy<ManagedSettings.Application> {
        switch policy {
        case .none:
            return .none
        case .all(except: let exceptions):
            var updated = exceptions
            updated.subtract(tokens)
            return updated.isEmpty ? .all() : .all(except: updated)
        case .specific(let categories, except: let exceptions):
            var updated = exceptions
            updated.subtract(tokens)
            return updated.isEmpty ? .specific(categories) : .specific(categories, except: updated)
        @unknown default:
            return policy
        }
    }
}
