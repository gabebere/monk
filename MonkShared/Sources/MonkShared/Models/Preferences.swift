import Foundation
import SwiftData

@Model
public final class Preferences {
    public var id: String = "singleton"
    @Attribute(originalName: "dailyGoalHours") public var weeklyGoalHours: Double = 0.0
    public var discardShortSessions: Bool?
    public var hasConvertedDailyGoal: Bool = false
    public var calendarIntegrationEnabled: Bool = false
    public var calendarCalendarIdentifier: String?

    public init(weeklyGoalHours: Double = 0.0,
                discardShortSessions: Bool? = nil,
                hasConvertedDailyGoal: Bool = false,
                calendarIntegrationEnabled: Bool = false,
                calendarCalendarIdentifier: String? = nil) {
        self.weeklyGoalHours = weeklyGoalHours
        self.discardShortSessions = discardShortSessions
        self.hasConvertedDailyGoal = hasConvertedDailyGoal
        self.calendarIntegrationEnabled = calendarIntegrationEnabled
        self.calendarCalendarIdentifier = calendarCalendarIdentifier
    }
}
