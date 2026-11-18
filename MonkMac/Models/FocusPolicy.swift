import Foundation

struct ApplicationDescriptor: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let bundleURL: URL
    let sourcePlatform: String?

    init(
        displayName: String,
        bundleIdentifier: String?,
        bundleURL: URL,
        sourcePlatform: String? = nil
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.sourcePlatform = sourcePlatform
        self.id = bundleIdentifier ?? bundleURL.standardizedFileURL.path
    }

    init(mobileApplication: CrossDeviceApplication) {
        displayName = mobileApplication.displayName
        bundleIdentifier = mobileApplication.sourceBundleIdentifier
        bundleURL = URL(
            fileURLWithPath: "/Monk/RemoteApplications/\(mobileApplication.id).app"
        )
        sourcePlatform = "iOS"
        id = mobileApplication.sourceBundleIdentifier ?? mobileApplication.id
    }

    var isRemoteMobileApplication: Bool {
        sourcePlatform == "iOS"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case bundleIdentifier
        case bundleURL
        case sourcePlatform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        bundleURL = try container.decode(URL.self, forKey: .bundleURL)
        sourcePlatform = try container.decodeIfPresent(String.self, forKey: .sourcePlatform)
    }
}

struct FocusPolicy: Identifiable, Hashable, Codable {
    let id: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let allowedApplications: [ApplicationDescriptor]
    let allowedDomains: [String]
    /// Full shared intent, including apps that exist only on another platform.
    /// Nil preserves backward compatibility with locally created or older persisted policies.
    let portableAllowedApplications: [CrossDeviceApplication]?

    init(
        id: UUID = UUID(),
        intention: String,
        startedAt: Date = .now,
        duration: TimeInterval,
        allowedApplications: [ApplicationDescriptor],
        allowedDomains: [String],
        portableAllowedApplications: [CrossDeviceApplication]? = nil
    ) {
        self.id = id
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = startedAt.addingTimeInterval(duration)
        self.allowedApplications = allowedApplications
        self.allowedDomains = allowedDomains
        self.portableAllowedApplications = portableAllowedApplications
    }

    init(
        id: UUID,
        intention: String,
        startedAt: Date,
        endsAt: Date,
        allowedApplications: [ApplicationDescriptor],
        allowedDomains: [String],
        portableAllowedApplications: [CrossDeviceApplication]? = nil
    ) {
        self.id = id
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.allowedApplications = allowedApplications
        self.allowedDomains = allowedDomains
        self.portableAllowedApplications = portableAllowedApplications
    }

    var allowedApplicationIDs: Set<String> {
        Set(allowedApplications.map(\.id))
    }
}

enum FocusDuration: Int, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case threeHours = 180

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    var label: String {
        switch self {
        case .fifteenMinutes: "15m"
        case .thirtyMinutes: "30m"
        case .oneHour: "1h"
        case .threeHours: "3h"
        }
    }
}
