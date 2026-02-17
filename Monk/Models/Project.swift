import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = Foundation.UUID()
    var title: String = ""
    var createdAt: Date = Foundation.Date()
    var gradientIndex: Int = 0
    var weeklyGoalHours: Double?
    var hardBlockEnabled: Bool = false
    var hardBlockSelectionData: Data?
    var isArchived: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.project) var sessions: [FocusSession]?
    @Relationship(deleteRule: .cascade, inverse: \FocusTask.project) var tasks: [FocusTask]?

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date = .now,
         gradientIndex: Int = 0,
         weeklyGoalHours: Double? = nil,
         hardBlockEnabled: Bool = false,
         hardBlockSelectionData: Data? = nil,
         isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.gradientIndex = gradientIndex
        self.weeklyGoalHours = weeklyGoalHours
        self.hardBlockEnabled = hardBlockEnabled
        self.hardBlockSelectionData = hardBlockSelectionData
        self.isArchived = isArchived
    }
}

extension Project {
    var canTrackWeeklyGoal: Bool { !isArchived }

    func setArchived(_ archived: Bool) {
        isArchived = archived
        if archived {
            weeklyGoalHours = nil
        }
    }

    func totalDuration(now: Date = .now) -> TimeInterval {
        sessionsUnwrapped.reduce(0) { partialResult, session in
            let end = session.endedAt ?? now
            guard end > session.startedAt else { return partialResult }
            return partialResult + end.timeIntervalSince(session.startedAt)
        }
    }

    var mostRecentSessionDate: Date? {
        sessionsUnwrapped.compactMap { $0.endedAt ?? $0.startedAt }.max()
    }

    var tasksUnwrapped: [FocusTask] { tasks ?? [] }
    var sessionsUnwrapped: [FocusSession] { sessions ?? [] }
}
