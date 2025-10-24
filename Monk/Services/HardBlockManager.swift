import Foundation
import FamilyControls
import ManagedSettings
import OSLog

@MainActor
final class HardBlockManager {
    static let shared = HardBlockManager()

    private let store = ManagedSettingsStore(named: .projectHardBlock)

    private init() {
        HardBlockStateStore.bootstrap()
    }

    func ensureAuthorization() async -> Bool {
        let center = AuthorizationCenter.shared
        switch center.authorizationStatus {
        case .approved:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                try await center.requestAuthorization(for: .individual)
                return center.authorizationStatus == .approved
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    @discardableResult
    func activateHardBlock(for project: Project) -> Bool {
        guard project.hardBlockEnabled,
              AuthorizationCenter.shared.authorizationStatus == .approved,
              let selection = decodeSelection(from: project.hardBlockSelectionData),
              hasShieldableTargets(selection) else {
            HardBlockStateStore.clear()
            return false
        }

        let categoryPolicy: ShieldSettings.ActivityCategoryPolicy<ManagedSettings.Application>?
        if selection.includeEntireCategory {
            let exceptions = selection.applicationTokens
            store.shield.applications = nil
            categoryPolicy = exceptions.isEmpty ? .all() : .all(except: exceptions)
        } else {
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            categoryPolicy = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        }

        store.shield.applicationCategories = categoryPolicy
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        HardBlockStateStore.save(selection: selection, projectTitle: project.title)
        return true
    }

    func deactivateHardBlock() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        HardBlockStateStore.clear()
    }

    func encodeSelection(_ selection: FamilyActivitySelection?) -> Data? {
        guard let selection else { return nil }
        return try? JSONEncoder().encode(selection)
    }

    func decodeSelection(from data: Data?) -> FamilyActivitySelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private func hasShieldableTargets(_ selection: FamilyActivitySelection) -> Bool {
        selection.includeEntireCategory ||
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }
}

private extension ManagedSettingsStore.Name {
    static let projectHardBlock = ManagedSettingsStore.Name("ProjectHardBlock")
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
