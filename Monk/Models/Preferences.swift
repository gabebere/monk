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
    var healthIncludeWorkouts: Bool = false
    var healthIncludeSleepInBed: Bool = false
    var healthIncludeSleepAsleep: Bool = false
    var healthLastImportAt: Date?
    var healthDefaultWorkoutProjectId: UUID?
    // Intent Mode (formerly Baseline) configuration
    var baselineEnabled: Bool = false
    var baselineScheduleEnabled: Bool = false
    var baselineScheduleData: Data?
    var baselineAlwaysAllowedSelectionData: Data?
    var baselineNeverBlockCategoriesSelectionData: Data?
    var baselineUnlockableAppsSelectionData: Data?

    init(weeklyGoalHours: Double = 0.0,
         discardShortSessions: Bool? = nil,
         hasConvertedDailyGoal: Bool = false,
         calendarIntegrationEnabled: Bool = false,
         calendarCalendarIdentifier: String? = nil,
         healthIncludeWorkouts: Bool = false,
         healthIncludeSleepInBed: Bool = false,
         healthIncludeSleepAsleep: Bool = false,
         healthLastImportAt: Date? = nil,
         healthDefaultWorkoutProjectId: UUID? = nil,
         baselineEnabled: Bool = false,
         baselineScheduleEnabled: Bool = false,
         baselineScheduleData: Data? = nil,
         baselineAlwaysAllowedSelectionData: Data? = nil,
         baselineNeverBlockCategoriesSelectionData: Data? = nil,
         baselineUnlockableAppsSelectionData: Data? = nil) {
        self.weeklyGoalHours = weeklyGoalHours
        self.discardShortSessions = discardShortSessions
        self.hasConvertedDailyGoal = hasConvertedDailyGoal
        self.calendarIntegrationEnabled = calendarIntegrationEnabled
        self.calendarCalendarIdentifier = calendarCalendarIdentifier
        self.healthIncludeWorkouts = healthIncludeWorkouts
        self.healthIncludeSleepInBed = healthIncludeSleepInBed
        self.healthIncludeSleepAsleep = healthIncludeSleepAsleep
        self.healthLastImportAt = healthLastImportAt
        self.healthDefaultWorkoutProjectId = healthDefaultWorkoutProjectId
        self.baselineEnabled = baselineEnabled
        self.baselineScheduleEnabled = baselineScheduleEnabled
        self.baselineScheduleData = baselineScheduleData
        self.baselineAlwaysAllowedSelectionData = baselineAlwaysAllowedSelectionData
        self.baselineNeverBlockCategoriesSelectionData = baselineNeverBlockCategoriesSelectionData
        self.baselineUnlockableAppsSelectionData = baselineUnlockableAppsSelectionData
    }
}
