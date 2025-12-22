import Foundation
import SwiftData

@Model
public final class Project {
    public var id: UUID = Foundation.UUID()
    public var title: String = ""
    public var createdAt: Date = Foundation.Date()
    public var gradientIndex: Int = 0
    public var weeklyGoalHours: Double?
    public var hardBlockEnabled: Bool = false
    public var hardBlockSelectionData: Data?
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.project) public var sessions: [FocusSession]?

    public init(id: UUID = UUID(),
                title: String,
                createdAt: Date = .now,
                gradientIndex: Int = 0,
                weeklyGoalHours: Double? = nil,
                hardBlockEnabled: Bool = false,
                hardBlockSelectionData: Data? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.gradientIndex = gradientIndex
        self.weeklyGoalHours = weeklyGoalHours
        self.hardBlockEnabled = hardBlockEnabled
        self.hardBlockSelectionData = hardBlockSelectionData
        self.sessions = []
    }
}

public extension Project {
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
