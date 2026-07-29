import DeviceActivity
import Foundation
import ManagedSettings

final class CrossDeviceFocusMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity.rawValue == CrossDeviceFocusShared.deviceActivityName else { return }

        let store = ManagedSettingsStore(
            named: ManagedSettingsStore.Name(CrossDeviceFocusShared.managedSettingsStoreName)
        )
        store.clearAllSettings()

        if let url = CrossDeviceFocusShared.stateURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
