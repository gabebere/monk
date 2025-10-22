import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import OSLog

struct SoftBlockUnlockRecord: Codable, Identifiable {
    let id: UUID
    let selectionData: Data
    let unlockStart: Date
    let unlockEnd: Date
    let waitDuration: TimeInterval
    let unlockDuration: TimeInterval
    let createdAt: Date

    enum Phase {
        case waiting(Int)
        case unlocked(Int)
        case expired
    }

    func phase(at date: Date = Date()) -> Phase {
        if date < unlockStart {
            let remaining = Int(ceil(unlockStart.timeIntervalSince(date)))
            return .waiting(max(remaining, 0))
        }

        if date < unlockEnd {
            let remaining = Int(ceil(unlockEnd.timeIntervalSince(date)))
            return .unlocked(max(remaining, 0))
        }

        return .expired
    }

    func selection() -> FamilyActivitySelection? {
        try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
    }

    func contains(application token: ManagedSettings.ApplicationToken) -> Bool {
        guard let selection = selection() else { return false }
        return selection.applicationTokens.contains(token)
    }
}

enum SoftBlockUnlockStore {
    private static let suiteName = "group.com.gbr.Monk"
    private static let fileName = "softBlockUnlockRecords.json"
    private static let logger = Logger(subsystem: "com.gbr.Monk", category: "SoftBlockUnlockStore")
    private static var didBootstrap = false

    static func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        let fm = FileManager.default
        if let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            logger.debug("Resolved app group container at \(containerURL.path, privacy: .public)")
            if !fm.fileExists(atPath: containerURL.path) {
                do {
                    try fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
                } catch {
                    logger.error("Failed to create app group directory: \(String(describing: error), privacy: .public)")
                }
            }
        } else {
            logger.error("Failed to resolve container URL for app group \(suiteName, privacy: .public). Check entitlements and provisioning.")
        }
    }

    static func allRecords() -> [SoftBlockUnlockRecord] {
        guard let data = readFile() else {
            return []
        }

        guard let records = try? JSONDecoder().decode([SoftBlockUnlockRecord].self, from: data) else {
            logger.error("Failed to decode unlock records JSON")
            return []
        }

        let now = Date()
        let filtered = records.filter { $0.unlockEnd > now }
        if filtered.count != records.count {
            saveRecords(filtered)
        }
        return filtered
    }

    static func upsert(_ record: SoftBlockUnlockRecord) {
        var records = allRecords().filter { $0.id != record.id }
        records.append(record)
        saveRecords(records)
    }

    static func remove(id: UUID) {
        let remaining = allRecords().filter { $0.id != id }
        saveRecords(remaining)
    }

    static func record(for activityName: DeviceActivity.DeviceActivityName) -> SoftBlockUnlockRecord? {
        allRecords().first { $0.id.uuidString == activityName.rawValue }
    }

    static func record(for applicationToken: ManagedSettings.ApplicationToken) -> SoftBlockUnlockRecord? {
        allRecords().first { $0.contains(application: applicationToken) }
    }

    static func clearExpired() {
        let active = allRecords()
        saveRecords(active)
    }

    static func removeAll() {
        saveRecords([])
    }

    private static func saveRecords(_ records: [SoftBlockUnlockRecord]) {
        guard let url = recordsURL() else { return }
        let fm = FileManager.default
        if records.isEmpty {
            try? fm.removeItem(at: url)
            return
        }

        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("Failed to save unlock records: \(String(describing: error), privacy: .public)")
        }
    }

    private static func readFile() -> Data? {
        guard let url = recordsURL() else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                logger.error("Failed to read unlock records: \(String(describing: error), privacy: .public)")
            }
            return nil
        }
    }

    private static func recordsURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else {
            logger.error("Cannot resolve records file URL because container is unavailable")
            return nil
        }
        return containerURL.appendingPathComponent(fileName, isDirectory: false)
    }
}

struct HardBlockState: Codable {
    let projectTitle: String?
    let selectionData: Data
    let activatedAt: Date

    func selection() -> FamilyActivitySelection? {
        try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
    }
}

enum HardBlockStateStore {
    private static let suiteName = "group.com.gbr.Monk"
    private static let fileName = "hardBlockState.json"
    private static let logger = Logger(subsystem: "com.gbr.Monk", category: "HardBlockStateStore")
    private static var didBootstrap = false

    static func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        let fm = FileManager.default
        if let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            logger.debug("Resolved hard block container at \(containerURL.path, privacy: .public)")
            if !fm.fileExists(atPath: containerURL.path) {
                do {
                    try fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
                } catch {
                    logger.error("Failed to create directory for hard block store: \(String(describing: error), privacy: .public)")
                }
            }
        } else {
            logger.error("Unable to resolve app group container for hard block store. Check entitlements.")
        }
    }

    static func save(selection: FamilyActivitySelection, projectTitle: String?) {
        guard let data = try? JSONEncoder().encode(selection) else {
            logger.error("Failed to encode FamilyActivitySelection for hard block state")
            return
        }

        let state = HardBlockState(
            projectTitle: projectTitle,
            selectionData: data,
            activatedAt: Date()
        )

        guard let url = stateURL() else { return }
        do {
            let encoded = try JSONEncoder().encode(state)
            try encoded.write(to: url, options: [.atomic])
        } catch {
            logger.error("Failed to write hard block state: \(String(describing: error), privacy: .public)")
        }
    }

    static func clear() {
        guard let url = stateURL() else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            if (error as NSError).code != NSFileNoSuchFileError {
                logger.error("Failed to clear hard block state: \(String(describing: error), privacy: .public)")
            }
        }
    }

    static func currentState() -> HardBlockState? {
        guard let url = stateURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HardBlockState.self, from: data)
    }

    static var projectTitle: String? {
        currentState()?.projectTitle
    }

    static var isActive: Bool {
        currentState() != nil
    }

    static func contains(application token: ManagedSettings.ApplicationToken?) -> Bool {
        guard let selection = currentState()?.selection() else { return false }

        if selection.includeEntireCategory {
            guard let token else { return true }
            return !selection.applicationTokens.contains(token)
        }

        if let token, selection.applicationTokens.contains(token) {
            return true
        }

        if !selection.categoryTokens.isEmpty {
            return true
        }

        return false
    }

    static func contains(category token: ManagedSettings.ActivityCategoryToken?) -> Bool {
        guard let token, let selection = currentState()?.selection() else { return false }
        if selection.includeEntireCategory { return true }
        return selection.categoryTokens.contains(token)
    }

    static func contains(webDomain token: ManagedSettings.WebDomainToken?) -> Bool {
        guard let token, let selection = currentState()?.selection() else { return false }
        return selection.webDomainTokens.contains(token)
    }

    private static func stateURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else {
            logger.error("Cannot resolve hard block state URL because the container is unavailable")
            return nil
        }
        return containerURL.appendingPathComponent(fileName, isDirectory: false)
    }
}
