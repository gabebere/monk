import Foundation
import SwiftData

@Model
final class Preferences {
    var id: String = "singleton"
    @Attribute(originalName: "dailyGoalHours") var weeklyGoalHours: Double = 0.0
    var discardShortSessions: Bool?
    var hasConvertedDailyGoal: Bool = false
    var calendarIntegrationEnabled: Bool = false
    var calendarCalendarIdentifier: String?

    init(weeklyGoalHours: Double = 0.0,
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
