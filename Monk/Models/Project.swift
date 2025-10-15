import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var softBlockEnabled: Bool
    var softBlockSelectionData: Data?
    var gradientIndex: Int
    var hardBlockEnabled: Bool
    var hardBlockSelectionData: Data?
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.project) var sessions: [FocusSession]

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
        sessions.reduce(0) { partialResult, session in
            let end = session.endedAt ?? now
            guard end > session.startedAt else { return partialResult }
            return partialResult + end.timeIntervalSince(session.startedAt)
        }
    }

    var mostRecentSessionDate: Date? {
        sessions.compactMap { $0.endedAt ?? $0.startedAt }.max()
    }
}
