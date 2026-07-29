import Foundation

struct CrossDeviceFocusState: Codable, Equatable {
    let sessionID: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let allowedDomains: [String]
    let allowedApplications: [CrossDeviceApplication]
    let allowedSelectionData: Data?
    let sourcePlatform: String?

    init(
        sessionID: UUID,
        intention: String,
        startedAt: Date,
        endsAt: Date,
        allowedDomains: [String],
        allowedApplications: [CrossDeviceApplication] = [],
        allowedSelectionData: Data? = nil,
        sourcePlatform: String? = nil
    ) {
        self.sessionID = sessionID
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.allowedDomains = allowedDomains
        self.allowedApplications = allowedApplications
        self.allowedSelectionData = allowedSelectionData
        self.sourcePlatform = sourcePlatform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        intention = try container.decode(String.self, forKey: .intention)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        allowedDomains = try container.decodeIfPresent([String].self, forKey: .allowedDomains) ?? []
        allowedApplications = try container.decodeIfPresent([CrossDeviceApplication].self, forKey: .allowedApplications) ?? []
        allowedSelectionData = try container.decodeIfPresent(Data.self, forKey: .allowedSelectionData)
        sourcePlatform = try container.decodeIfPresent(String.self, forKey: .sourcePlatform)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(intention, forKey: .intention)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endsAt, forKey: .endsAt)
        try container.encode(allowedDomains, forKey: .allowedDomains)
        try container.encode(allowedApplications, forKey: .allowedApplications)
        try container.encodeIfPresent(allowedSelectionData, forKey: .allowedSelectionData)
        try container.encodeIfPresent(sourcePlatform, forKey: .sourcePlatform)
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case intention
        case startedAt
        case endsAt
        case allowedDomains
        case allowedApplications
        case allowedSelectionData
        case sourcePlatform
    }
}

enum CrossDeviceFocusShared {
    static let appGroupIdentifier = "group.com.gbr.Monk"
    static let stateFileName = "crossDeviceFocusState.json"
    static let managedSettingsStoreName = "CrossDeviceFocus"
    static let deviceActivityName = "CrossDeviceFocusExpiry"

    static func stateURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(stateFileName, isDirectory: false)
    }
}
