import CloudKit
import Foundation

enum CrossDeviceCatalogPlatform: String, Codable {
    case macOS = "macOS"
    case iPhone = "iOS"
    case iPad = "iPadOS"

    var legacyRecordName: String {
        switch self {
        case .macOS: CrossDeviceCloudRecord.macApplicationCatalogName
        case .iPhone: CrossDeviceCloudRecord.iPhoneApplicationCatalogName
        case .iPad: CrossDeviceCloudRecord.iPadApplicationCatalogName
        }
    }
}

enum CrossDeviceCatalogDevice {
    private static let identifierKey = "crossDeviceFocus.catalogDeviceID.v1"

    /// Random installation identity, never a hardware ID, account ID, or device name.
    static func identifier(in defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: identifierKey),
           let identifier = UUID(uuidString: stored) {
            return identifier.uuidString.lowercased()
        }
        let identifier = UUID().uuidString.lowercased()
        defaults.set(identifier, forKey: identifierKey)
        return identifier
    }
}

struct CrossDeviceApplicationCatalog {
    static let schemaVersion = 1
    static let maximumApplications = 500
    static let maximumAge: TimeInterval = 90 * 24 * 60 * 60

    let deviceID: String
    let platform: CrossDeviceCatalogPlatform
    let updatedAt: Date
    let applications: [CrossDeviceApplication]
    let isLegacy: Bool

    var recordName: String {
        isLegacy ? platform.legacyRecordName : "\(platform.legacyRecordName)-\(deviceID)"
    }

    init(
        deviceID: String,
        platform: CrossDeviceCatalogPlatform,
        updatedAt: Date = Date(),
        applications: [CrossDeviceApplication]
    ) {
        self.deviceID = deviceID.lowercased()
        self.platform = platform
        self.updatedAt = updatedAt
        self.applications = Array(Self.deduplicated(applications).prefix(Self.maximumApplications))
        self.isLegacy = false
    }

    init?(record: CKRecord) {
        guard record.recordType == CrossDeviceCloudRecord.applicationCatalogType else { return nil }
        let recordVersion = (record["schemaVersion"] as? NSNumber)?.intValue ?? 0
        guard (0...Self.schemaVersion).contains(recordVersion) else { return nil }

        let resolvedPlatform: CrossDeviceCatalogPlatform?
        if let value = record["platform"] as? String {
            resolvedPlatform = CrossDeviceCatalogPlatform(rawValue: value)
        } else {
            resolvedPlatform = [CrossDeviceCatalogPlatform.macOS, .iPhone, .iPad].first {
                $0.legacyRecordName == record.recordID.recordName
            }
        }
        guard let platform = resolvedPlatform else { return nil }

        let identifiers = record["applicationIDs"] as? [String] ?? []
        let names = record["applicationNames"] as? [String] ?? []
        let bundles = record["applicationBundleIdentifiers"] as? [String] ?? []
        // Parallel arrays are the existing wire contract. Reject a malformed
        // catalog instead of silently assigning an app another app's identity.
        guard identifiers.count == names.count,
              identifiers.count <= Self.maximumApplications,
              bundles.isEmpty || bundles.count == identifiers.count else { return nil }
        let applications = identifiers.indices.map { index in
            CrossDeviceApplication(
                id: identifiers[index],
                displayName: names[index],
                sourceBundleIdentifier: bundles.isEmpty || bundles[index].isEmpty ? nil : bundles[index]
            )
        }
        let deviceID = record["deviceID"] as? String
        if let deviceID {
            guard let identifier = UUID(uuidString: deviceID) else { return nil }
            self.deviceID = identifier.uuidString.lowercased()
        } else {
            guard record.recordID.recordName == platform.legacyRecordName else { return nil }
            self.deviceID = "legacy:\(platform.rawValue)"
        }
        self.platform = platform
        self.updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? .distantPast
        self.applications = Self.deduplicated(applications)
        self.isLegacy = deviceID == nil
    }

    func write(to record: CKRecord) {
        record["schemaVersion"] = NSNumber(value: Self.schemaVersion)
        record["deviceID"] = deviceID as CKRecordValue
        record["platform"] = platform.rawValue as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        record["applicationIDs"] = applications.map(\.id) as NSArray
        record["applicationNames"] = applications.map(\.displayName) as NSArray
        record["applicationBundleIdentifiers"] = applications.map {
            $0.sourceBundleIdentifier ?? ""
        } as NSArray
    }

    /// Fetches every page in the user's private database. Older schemas that do
    /// not support catalog queries can still supply their three legacy records.
    static func fetch(from database: CKDatabase) async throws -> [Self] {
        do {
            let query = CKQuery(
                recordType: CrossDeviceCloudRecord.applicationCatalogType,
                predicate: NSPredicate(value: true)
            )
            var page = try await database.records(matching: query)
            var catalogs: [Self] = []
            while true {
                for (_, result) in page.matchResults {
                    let record = try result.get()
                    if let catalog = Self(record: record) { catalogs.append(catalog) }
                }
                guard let cursor = page.queryCursor else { return catalogs }
                page = try await database.records(continuingMatchFrom: cursor)
            }
        } catch let error as CKError where
            error.code == .invalidArguments ||
            error.code == .serverRejectedRequest ||
            error.code == .unknownItem {
            return try await fetchLegacyCatalogs(from: database)
        }
    }

    static func mergedApplications(
        from catalogs: [Self],
        excludingDeviceID: String? = nil,
        now: Date = Date()
    ) -> [CrossDeviceApplication] {
        let current = catalogs.filter {
            $0.deviceID != excludingDeviceID?.lowercased() &&
                // Legacy catalogs without dates remain a compatibility source.
                ($0.updatedAt == .distantPast || now.timeIntervalSince($0.updatedAt) <= maximumAge)
        }
        let modernPlatforms = Set(current.filter { !$0.isLegacy }.map(\.platform))
        let ordered = current.filter {
            !$0.isLegacy || !modernPlatforms.contains($0.platform)
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.recordName < $1.recordName
        }
        return deduplicated(ordered.flatMap(\.applications)).sorted {
            let comparison = $0.displayName.localizedStandardCompare($1.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.id < $1.id
        }
    }

    private static func deduplicated(
        _ applications: [CrossDeviceApplication]
    ) -> [CrossDeviceApplication] {
        var seen = Set<String>()
        return applications.filter {
            seen.insert(CrossDeviceApplication.stableID(
                displayName: $0.displayName,
                bundleIdentifier: $0.sourceBundleIdentifier
            )).inserted
        }
    }

    private static func fetchLegacyCatalogs(from database: CKDatabase) async throws -> [Self] {
        var catalogs: [Self] = []
        for platform in [CrossDeviceCatalogPlatform.macOS, .iPhone, .iPad] {
            do {
                let record = try await database.record(for: CKRecord.ID(recordName: platform.legacyRecordName))
                if let catalog = Self(record: record) { catalogs.append(catalog) }
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
        return catalogs
    }
}
