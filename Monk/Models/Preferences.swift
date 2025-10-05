import Foundation
import SwiftData

@Model
final class Preferences {
    @Attribute(.unique) var id: String = "singleton"
    @Attribute(originalName: "dailyGoalHours") var weeklyGoalHours: Double = 40.0
    @Attribute(originalName: "nudgeMinutes") private var legacyNudgeMinutes: Int? = nil
    @Attribute(originalName: "iCloudSyncEnabled") private var legacyICloudSyncEnabled: Bool = true
    // Optional to allow lightweight migration from existing stores.
    // Treat nil as false in code paths.
    var discardShortSessions: Bool?
    var softBlockEnabled: Bool = false
    var softBlockSelectionData: Data?

    init(weeklyGoalHours: Double = 40.0, discardShortSessions: Bool? = nil) {
        self.weeklyGoalHours = weeklyGoalHours
        self.discardShortSessions = discardShortSessions
    }
}
