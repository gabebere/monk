import Foundation
import SwiftData

@Model
final class Preferences {
    var id: String = "singleton"
    @Attribute(originalName: "dailyGoalHours") var weeklyGoalHours: Double = 40.0
    var discardShortSessions: Bool?

    init(weeklyGoalHours: Double = 40.0, discardShortSessions: Bool? = nil) {
        self.weeklyGoalHours = weeklyGoalHours
        self.discardShortSessions = discardShortSessions
    }
}
