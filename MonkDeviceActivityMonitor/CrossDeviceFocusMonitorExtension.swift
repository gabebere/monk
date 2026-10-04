import DeviceActivity
import Foundation
import ManagedSettings

final class CrossDeviceFocusMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity.rawValue == CrossDeviceFocusShared.deviceActivityName {
            // Managed Settings intentionally remain in place at zero. The main app
            // asks whether to extend or end before it changes enforcement.
            return
        }

        guard activity.rawValue.hasPrefix(TemporaryApplicationGrantStore.activityNamePrefix),
              let defaults = UserDefaults(
                  suiteName: CrossDeviceFocusShared.appGroupIdentifier
              ) else {
            return
        }

        let grants = TemporaryApplicationGrantStore.activeGrants(from: defaults)
        TemporaryApplicationGrantStore.save(grants, to: defaults)
        guard defaults.bool(
            forKey: TemporaryApplicationGrantStore.applicationShieldIsActiveKey
        ) else {
            return
        }

        let baseTokens = TemporaryApplicationGrantStore.baseAllowedTokens(from: defaults)
        let allowedTokens = TemporaryApplicationGrantStore.combinedAllowedTokens(
            baseTokens: baseTokens,
            grants: grants
        )
        let store = ManagedSettingsStore(named: .crossDeviceFocus)
        store.shield.applications = nil
        store.shield.applicationCategories = .all(except: allowedTokens)
    }
}

private extension ManagedSettingsStore.Name {
    static let crossDeviceFocus = ManagedSettingsStore.Name(
        CrossDeviceFocusShared.managedSettingsStoreName
    )
}
