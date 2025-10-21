import ActivityKit
import Foundation

struct FocusSessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var projectName: String?
        var focusScore: Int?
        var focusScoreDelta: Int?
        var focusScoreLabel: String?
        var weeklyGoalSeconds: TimeInterval?
        var weeklyCompletedSeconds: TimeInterval?
        var weeklyRemainingSeconds: TimeInterval?
        var dailyTargetSeconds: TimeInterval?
        var todayGoalSeconds: TimeInterval?
        var todayCompletedSeconds: TimeInterval?
        var todayRemainingSeconds: TimeInterval?
        var timerInterval: ClosedRange<Date>
        var isPaused: Bool
    }

    var sessionID: UUID
}
