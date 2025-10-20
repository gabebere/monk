import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = Foundation.UUID()
    var title: String = ""
    var createdAt: Date = Foundation.Date()
    var softBlockEnabled: Bool = false
    var softBlockSelectionData: Data?
    var gradientIndex: Int = 0
    var hardBlockEnabled: Bool = false
    var hardBlockSelectionData: Data?
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.project) var sessions: [FocusSession]?

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date = .now,
         softBlockEnabled: Bool = false,
         softBlockSelectionData: Data? = nil,
         gradientIndex: Int = 0,
         hardBlockEnabled: Bool = false,
         hardBlockSelectionData: Data? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.softBlockEnabled = softBlockEnabled
        self.softBlockSelectionData = softBlockSelectionData
        self.gradientIndex = gradientIndex
        self.hardBlockEnabled = hardBlockEnabled
        self.hardBlockSelectionData = hardBlockSelectionData
        self.sessions = []
    }
}

extension Project {
    func totalDuration(now: Date = .now) -> TimeInterval {
        sessions?.reduce(0) { partialResult, session in
            let end = session.endedAt ?? now
            guard end > session.startedAt else { return partialResult }
            return partialResult + end.timeIntervalSince(session.startedAt)
        } ?? 0
    }

    var mostRecentSessionDate: Date? {
        sessions?.compactMap { $0.endedAt ?? $0.startedAt }.max()
    }
}
