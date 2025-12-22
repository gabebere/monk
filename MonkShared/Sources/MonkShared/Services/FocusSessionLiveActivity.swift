#if canImport(ActivityKit)
import ActivityKit
import Foundation

public struct FocusSessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var projectName: String?
        public var weeklyGoalSeconds: TimeInterval?
        public var weeklyCompletedSeconds: TimeInterval?
        public var weeklyRemainingSeconds: TimeInterval?
        public var dailyTargetSeconds: TimeInterval?
        public var todayGoalSeconds: TimeInterval?
        public var todayCompletedSeconds: TimeInterval?
        public var todayRemainingSeconds: TimeInterval?
        public var timerInterval: ClosedRange<Date>
        public var isPaused: Bool
    }

    public var sessionID: UUID
}
#endif
