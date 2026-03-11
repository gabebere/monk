import Foundation
import SwiftData

@Model
final class Preferences {
    var id: String = "singleton"
    @Attribute(originalName: "dailyGoalHours") var weeklyGoalHours: Double = 0.0
    var discardShortSessions: Bool?
    var hasConvertedDailyGoal: Bool = false
    var focusNudgesEnabled: Bool = true
    var focusDailySummaryEnabled: Bool = true
    var calendarIntegrationEnabled: Bool = false
    var calendarCalendarIdentifier: String?
    var healthIncludeWorkouts: Bool = false
    var healthIncludeSleepInBed: Bool = false
    var healthIncludeSleepAsleep: Bool = false
    var healthLastImportAt: Date?
    var healthDefaultWorkoutProjectId: UUID?

    init(weeklyGoalHours: Double = 0.0,
         discardShortSessions: Bool? = nil,
         hasConvertedDailyGoal: Bool = false,
         focusNudgesEnabled: Bool = true,
         focusDailySummaryEnabled: Bool = true,
         calendarIntegrationEnabled: Bool = false,
         calendarCalendarIdentifier: String? = nil,
         healthIncludeWorkouts: Bool = false,
         healthIncludeSleepInBed: Bool = false,
         healthIncludeSleepAsleep: Bool = false,
         healthLastImportAt: Date? = nil,
         healthDefaultWorkoutProjectId: UUID? = nil) {
        self.weeklyGoalHours = weeklyGoalHours
        self.discardShortSessions = discardShortSessions
        self.hasConvertedDailyGoal = hasConvertedDailyGoal
        self.focusNudgesEnabled = focusNudgesEnabled
        self.focusDailySummaryEnabled = focusDailySummaryEnabled
        self.calendarIntegrationEnabled = calendarIntegrationEnabled
        self.calendarCalendarIdentifier = calendarCalendarIdentifier
        self.healthIncludeWorkouts = healthIncludeWorkouts
        self.healthIncludeSleepInBed = healthIncludeSleepInBed
        self.healthIncludeSleepAsleep = healthIncludeSleepAsleep
        self.healthLastImportAt = healthLastImportAt
        self.healthDefaultWorkoutProjectId = healthDefaultWorkoutProjectId
    }
}
