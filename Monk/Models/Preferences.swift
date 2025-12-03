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
    /// Tracks whether the new onboarding flow has been completed (versioned for future updates).
    var onboardingVersion: Int = 0
    /// Persists where the user is within onboarding so we can resume after relaunch.
    var onboardingPendingCardRaw: String?
    var onboardingActiveStageRaw: String?

    init(weeklyGoalHours: Double = 0.0,
         discardShortSessions: Bool? = nil,
         hasConvertedDailyGoal: Bool = false,
         calendarIntegrationEnabled: Bool = false,
         calendarCalendarIdentifier: String? = nil,
         onboardingVersion: Int = 0,
         onboardingPendingCardRaw: String? = nil,
         onboardingActiveStageRaw: String? = nil) {
        self.weeklyGoalHours = weeklyGoalHours
        self.discardShortSessions = discardShortSessions
        self.hasConvertedDailyGoal = hasConvertedDailyGoal
        self.calendarIntegrationEnabled = calendarIntegrationEnabled
        self.calendarCalendarIdentifier = calendarCalendarIdentifier
        self.onboardingVersion = onboardingVersion
        self.onboardingPendingCardRaw = onboardingPendingCardRaw
        self.onboardingActiveStageRaw = onboardingActiveStageRaw
    }
}
