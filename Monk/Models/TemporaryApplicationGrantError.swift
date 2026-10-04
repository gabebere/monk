import Foundation

enum TemporaryApplicationGrantError: LocalizedError {
    case applicationCatalogPermissionRequired
    case applicationNotFound
    case invalidDuration
    case monkIsNotBlocking
    case noApplications
    case screenTimePermissionRequired
    case tooManyConcurrentGrants

    var errorDescription: String? {
        switch self {
        case .applicationCatalogPermissionRequired:
            "Open Monk once and allow app-name access before using Siri."
        case .applicationNotFound:
            "That app is not installed on this device."
        case .invalidDuration:
            "Choose a duration between one minute and one year."
        case .monkIsNotBlocking:
            "Monk is not currently blocking apps on this device."
        case .noApplications:
            "Choose at least one app to temporarily allow."
        case .screenTimePermissionRequired:
            "Open Monk once and allow Screen Time access before using Siri."
        case .tooManyConcurrentGrants:
            "Ten temporary app grants are already active. Let one expire before adding another."
        }
    }
}
