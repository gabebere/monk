import Foundation
import SwiftData

@Model
final class Preferences {
    @Attribute(.unique) var id: String = "singleton"
    var dailyGoalHours: Double
    var nudgeMinutes: Int? // nil => Off
    var iCloudSyncEnabled: Bool
    // Optional to allow lightweight migration from existing stores.
    // Treat nil as false in code paths.
    var discardShortSessions: Bool?

    init(dailyGoalHours: Double = 4.0, nudgeMinutes: Int? = 50, iCloudSyncEnabled: Bool = false, discardShortSessions: Bool? = nil) {
        self.dailyGoalHours = dailyGoalHours
        self.nudgeMinutes = nudgeMinutes
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.discardShortSessions = discardShortSessions
    }
}
