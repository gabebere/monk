import CloudKit
import Foundation

struct RemoteFocusCommitment {
    let sessionID: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let allowedDomains: [String]
    let allowedApplications: [CrossDeviceApplication]
    let sourcePlatform: String?
    let isEnded: Bool

    init?(record: CKRecord) {
        guard record.recordType == CrossDeviceFocusService.recordType,
              let sessionIDString = record["sessionID"] as? String,
              let sessionID = UUID(uuidString: sessionIDString),
              let intention = record["intention"] as? String,
              let startedAt = record["startedAt"] as? Date,
              let endsAt = record["endsAt"] as? Date else {
            return nil
        }

        self.sessionID = sessionID
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = endsAt
        allowedDomains = record["allowedDomains"] as? [String] ?? []
        allowedApplications = Self.decodeApplications(from: record)
        sourcePlatform = record["sourcePlatform"] as? String
        isEnded = (record["sessionStatus"] as? String) == "ended"
    }

    private static func decodeApplications(from record: CKRecord) -> [CrossDeviceApplication] {
        let identifiers = record["allowedApplicationIDs"] as? [String] ?? []
        let names = record["allowedApplicationNames"] as? [String] ?? []
        let bundleIdentifiers = record["allowedApplicationBundleIdentifiers"] as? [String] ?? []

        return identifiers.indices.compactMap { index in
            guard names.indices.contains(index) else { return nil }
            let bundleIdentifier = bundleIdentifiers.indices.contains(index)
                && !bundleIdentifiers[index].isEmpty
                ? bundleIdentifiers[index]
                : nil
            return CrossDeviceApplication(
                id: identifiers[index],
                displayName: names[index],
                sourceBundleIdentifier: bundleIdentifier
            )
        }
    }
}

struct RemoteDefaultAccessConfiguration {
    let enabled: Bool
    let applications: [CrossDeviceApplication]
    let updatedAt: Date

    init?(record: CKRecord) {
        guard record.recordType == CrossDeviceCloudRecord.defaultAccessType,
              let enabledNumber = record["enabled"] as? NSNumber,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        enabled = enabledNumber.boolValue
        self.updatedAt = updatedAt

        let identifiers = record["applicationIDs"] as? [String] ?? []
        let names = record["applicationNames"] as? [String] ?? []
        let bundleIdentifiers = record["applicationBundleIdentifiers"] as? [String] ?? []
        applications = identifiers.indices.compactMap { index in
            guard names.indices.contains(index) else { return nil }
            let bundleIdentifier = bundleIdentifiers.indices.contains(index)
                && !bundleIdentifiers[index].isEmpty
                ? bundleIdentifiers[index]
                : nil
            return CrossDeviceApplication(
                id: identifiers[index],
                displayName: names[index],
                sourceBundleIdentifier: bundleIdentifier
            )
        }
    }
}
