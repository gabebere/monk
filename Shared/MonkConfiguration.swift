import Foundation

enum MonkConfiguration {
    static var cloudKitContainerIdentifier: String {
        requiredInfoValue(forKey: "MonkCloudKitContainerIdentifier")
    }

    static var appGroupIdentifier: String {
        requiredInfoValue(forKey: "MonkAppGroupIdentifier")
    }

    static var loggingSubsystem: String {
        Bundle.main.bundleIdentifier ?? "Monk"
    }

    private static func requiredInfoValue(forKey key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            preconditionFailure("Missing required Info.plist value for \(key).")
        }
        return value
    }
}
