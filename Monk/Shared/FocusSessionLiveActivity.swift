import ActivityKit
import Foundation

struct FocusSessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String?
        var startedAt: Date
        var timerInterval: ClosedRange<Date>
        var isPaused: Bool
    }

    var sessionID: UUID
}
