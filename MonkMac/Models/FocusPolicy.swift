import Foundation

struct ApplicationDescriptor: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let bundleURL: URL

    init(displayName: String, bundleIdentifier: String?, bundleURL: URL) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.id = bundleIdentifier ?? bundleURL.standardizedFileURL.path
    }
}

struct FocusPolicy: Identifiable, Hashable, Codable {
    let id: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let allowedApplications: [ApplicationDescriptor]
    let allowedDomains: [String]

    init(
        id: UUID = UUID(),
        intention: String,
        startedAt: Date = .now,
        duration: TimeInterval,
        allowedApplications: [ApplicationDescriptor],
        allowedDomains: [String]
    ) {
        self.id = id
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = startedAt.addingTimeInterval(duration)
        self.allowedApplications = allowedApplications
        self.allowedDomains = allowedDomains
    }

    init(
        id: UUID,
        intention: String,
        startedAt: Date,
        endsAt: Date,
        allowedApplications: [ApplicationDescriptor],
        allowedDomains: [String]
    ) {
        self.id = id
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.allowedApplications = allowedApplications
        self.allowedDomains = allowedDomains
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
