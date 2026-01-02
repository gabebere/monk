import Foundation
import SwiftData

enum DemoDataSeeder {
    private static let seedKey = "demoDataSeeded"

    static func seedIfNeeded(modelContext: ModelContext) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: seedKey) { return }

        let hasSessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>()))?.isEmpty == false
        let hasProjects = (try? modelContext.fetch(FetchDescriptor<Project>()))?.isEmpty == false
        if hasSessions || hasProjects {
            defaults.set(true, forKey: seedKey)
            return
        }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()

        let thesis = Project(title: "Thesis Draft", createdAt: now.addingTimeInterval(-14 * 86400), gradientIndex: 0, weeklyGoalHours: 8)
        let product = Project(title: "Product Launch", createdAt: now.addingTimeInterval(-10 * 86400), gradientIndex: 1, weeklyGoalHours: 10)
        let reading = Project(title: "Reading List", createdAt: now.addingTimeInterval(-7 * 86400), gradientIndex: 2, weeklyGoalHours: 5)

        let projects = [thesis, product, reading]
        projects.forEach { modelContext.insert($0) }

        func day(_ daysAgo: Int, hour: Int, minutes: Int, durationMinutes: Int, project: Project?) {
            guard let start = calendar.date(bySettingHour: hour, minute: minutes, second: 0, of: now.addingTimeInterval(TimeInterval(-daysAgo) * 86400)) else { return }
            let end = start.addingTimeInterval(TimeInterval(durationMinutes) * 60)
            let session = FocusSession(startedAt: start, endedAt: end, project: project)
            modelContext.insert(session)
        }

        day(1, hour: 9, minutes: 0, durationMinutes: 90, project: thesis)
        day(1, hour: 14, minutes: 30, durationMinutes: 75, project: product)
        day(2, hour: 8, minutes: 45, durationMinutes: 60, project: thesis)
        day(3, hour: 19, minutes: 15, durationMinutes: 45, project: reading)
        day(5, hour: 10, minutes: 0, durationMinutes: 120, project: product)
        day(6, hour: 7, minutes: 30, durationMinutes: 50, project: thesis)
        day(7, hour: 20, minutes: 0, durationMinutes: 40, project: reading)

        if let prefs = (try? modelContext.fetch(FetchDescriptor<Preferences>()))?.first {
            if prefs.weeklyGoalHours <= 0 { prefs.weeklyGoalHours = 40 }
        } else {
            let prefs = Preferences(weeklyGoalHours: 40, discardShortSessions: false, hasConvertedDailyGoal: true)
            modelContext.insert(prefs)
        }

        _ = modelContext.saveOrRollback()
        defaults.set(true, forKey: seedKey)
    }
}
