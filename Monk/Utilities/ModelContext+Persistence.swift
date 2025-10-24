import OSLog
import SwiftData

extension ModelContext {
    @discardableResult
    func saveOrRollback(logger: Logger = .persistence,
                        file: StaticString = #fileID,
                        line: UInt = #line) -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            logger.error("Failed to save ModelContext at \(file, privacy: .public):\(line, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            rollback()
            return false
        }
    }
}

private extension Logger {
    static let persistence = Logger(subsystem: "com.gbr.Monk", category: "Persistence")
}
