import Foundation
import ManagedSettings
import FamilyControls
import OSLog

struct IntentAppIndexEntry: Codable {
    let applicationTokenData: Data
    let displayName: String
    let normalizedName: String

    var token: ManagedSettings.ApplicationToken? {
        try? JSONDecoder().decode(ManagedSettings.ApplicationToken.self, from: applicationTokenData)
    }
}

enum IntentAppIndexStore {
    private static let suiteName = "group.com.gbr.Monk"
    private static let fileName = "intentAppIndex.json"
    private static let logger = Logger(subsystem: "com.gbr.Monk", category: "IntentAppIndexStore")
    private static var didBootstrap = false

    static func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        let fm = FileManager.default
        if let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            if !fm.fileExists(atPath: containerURL.path) {
                try? fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
            }
        } else {
            logger.error("Unable to resolve app group container for intent app index.")
        }
    }

    static func load() -> [IntentAppIndexEntry] {
        guard let url = stateURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([IntentAppIndexEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ entries: [IntentAppIndexEntry]) {
        guard let url = stateURL() else { return }
        do {
            let encoded = try JSONEncoder().encode(entries)
            try encoded.write(to: url, options: [.atomic])
        } catch {
            logger.error("Failed to write intent app index: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Build an index from a FamilyActivitySelection of unlockable apps.
    static func rebuild(from selectionData: Data?) {
        guard let selectionData,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) else {
            save([])
            return
        }

        let entries: [IntentAppIndexEntry] = selection.applicationTokens.compactMap { token in
            let app = ManagedSettings.Application(token: token)
            guard let name = app.localizedDisplayName else { return nil }
            let normalized = normalize(name)
            guard let data = try? JSONEncoder().encode(token) else { return nil }
            return IntentAppIndexEntry(applicationTokenData: data,
                                       displayName: name,
                                       normalizedName: normalized)
        }
        save(entries)
        logger.debug("Rebuilt intent app index with \(entries.count, privacy: .public) entries")
    }

    /// Return a unique match for the given normalized prefix, or nil if ambiguous/none.
    static func resolve(prefix raw: String) -> IntentAppIndexEntry? {
        let query = normalize(raw)
        guard !query.isEmpty else { return nil }
        let matches = load().filter { $0.normalizedName.hasPrefix(query) }
        return matches.count == 1 ? matches.first : nil
    }

    static func normalize(_ name: String) -> String {
        let lowered = name.lowercased()
        let trimmed = lowered.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.replacingOccurrences(of: "[\\.,!?:;'\"()\\[\\]{}\\-_]+", with: " ", options: .regularExpression)
        let collapsed = stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stateURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else {
            logger.error("Cannot resolve intent app index URL because the container is unavailable")
            return nil
        }
        return containerURL.appendingPathComponent(fileName, isDirectory: false)
    }
}
