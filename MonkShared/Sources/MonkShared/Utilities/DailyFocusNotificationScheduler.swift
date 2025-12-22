import Foundation
import SwiftData
import UserNotifications

public enum DailyFocusNotificationScheduler {
    private static let identifier = "daily_focus_summary_9pm"
    private static let debugIdentifier = "daily_focus_summary_debug"

    /// Schedules a daily 9pm local notification summarizing the last 24h of focus time.
    @MainActor
    public static func scheduleDailySummary(modelContext: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
            return
        }

        let totalSeconds = totalFocusSeconds(inLast: 24 * 3600, modelContext: modelContext, now: now)
        let formatted = formattedDuration(totalSeconds)

        let content = UNMutableNotificationContent()
        content.title = "Focus recap"
        content.body = "You focused \(formatted) since yesterday."
        content.sound = .default

        let triggerDate = nextNinePM(from: now)
        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        // Replace any existing scheduled recap to avoid duplicates.
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule daily focus recap: \(error.localizedDescription)")
        }
    }

    /// Sends a debug notification in ~5 seconds with the same payload for quick validation.
    @MainActor
    public static func sendDebugNotification(modelContext: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
            print("Debug notification skipped: notifications not authorized")
            return
        }

        let totalSeconds = totalFocusSeconds(inLast: 24 * 3600, modelContext: modelContext, now: now)
        let formatted = formattedDuration(totalSeconds)

        let content = UNMutableNotificationContent()
        content.title = "Debug focus recap"
        content.body = "You focused \(formatted) since yesterday. (debug)"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [debugIdentifier])

        let request = UNNotificationRequest(identifier: debugIdentifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            print("Scheduled debug focus notification in 5s")
        } catch {
            print("Failed to schedule debug focus notification: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func totalFocusSeconds(inLast interval: TimeInterval, modelContext: ModelContext, now: Date) -> TimeInterval {
        let windowStart = now.addingTimeInterval(-interval)
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { s in
                s.startedAt < now && (s.endedAt ?? now) > windowStart
            }
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []

        var total: TimeInterval = 0
        for session in sessions {
            let start = max(session.startedAt, windowStart)
            let end = min(session.endedAt ?? now, now)
            if end > start {
                total += end.timeIntervalSince(start)
            }
        }
        return total
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        if hours >= 1.0 {
            return String(format: "%.1f hours", hours)
        }
        let minutes = Int(round(seconds / 60))
        return "\(minutes) minutes"
    }

    private static func nextNinePM(from date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = 21
        comps.minute = 0
        comps.second = 0
        let todayNine = calendar.date(from: comps) ?? date
        if todayNine <= date {
            return calendar.date(byAdding: .day, value: 1, to: todayNine) ?? date.addingTimeInterval(24 * 3600)
        }
        return todayNine
    }
}
