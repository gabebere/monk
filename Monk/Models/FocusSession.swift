import Foundation
import SwiftData

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date? // nil => in progress
    var moodScore: Int?
    var feelings: [String]
    var tags: [String]

    init(id: UUID = UUID(), startedAt: Date = .now, endedAt: Date? = nil, moodScore: Int? = nil, feelings: [String] = [], tags: [String] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.moodScore = moodScore
        self.feelings = feelings
        self.tags = tags
    }
}

extension FocusSession {
    var isInProgress: Bool { endedAt == nil }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}
