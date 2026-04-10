import Foundation

enum FeatureFlags {
    static var tasksV1Enabled: Bool {
        boolFlag("feature.tasksV1Enabled", defaultValue: true)
    }

    static var monk2Enabled: Bool {
        boolFlag("feature.monk2.enabled", defaultValue: true)
    }

    static var homeSingleHubEnabled: Bool {
        monk2Enabled && boolFlag("feature.monk2.homeSingleHub", defaultValue: true)
    }

    static var remindersProjectListsEnabled: Bool {
        monk2Enabled && boolFlag("feature.monk2.remindersProjectLists", defaultValue: false)
    }

    static var quickUnlockEnabled: Bool {
        monk2Enabled && boolFlag("feature.monk2.quickUnlock", defaultValue: false)
    }

    static var focusFullscreenEnabled: Bool {
        monk2Enabled && boolFlag("feature.monk2.focusFullscreen", defaultValue: false)
    }
}

private extension FeatureFlags {
    static func boolFlag(_ key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}
