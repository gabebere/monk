import Foundation
import SwiftData

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date? // nil => in progress
    var moodScore: Int?
    var project: Project?

    init(id: UUID = UUID(),
         startedAt: Date = .now,
         endedAt: Date? = nil,
         moodScore: Int? = nil,
         project: Project? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.moodScore = moodScore
        self.project = project
    }
}

extension FocusSession {
    var isInProgress: Bool { endedAt == nil }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}
