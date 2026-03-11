import Foundation

@MainActor
final class UsageAnalyticsService {
    static let shared = UsageAnalyticsService()

    private let defaults = UserDefaults.standard
    private let calendar: Calendar
    private let dayFormatter: DateFormatter
    private let appOpenedPrefix = "analytics.app_opened.last_day."
    private let dailySnapshotSentPrefix = "analytics.daily_focus_snapshot.sent."
    private let dailySnapshotLastPrefix = "analytics.daily_focus_snapshot.last_seconds."
    private let authUserIDKey = "auth.userID"

    private init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        var configured = calendar
        configured.locale = .autoupdatingCurrent
        configured.timeZone = .autoupdatingCurrent
        self.calendar = configured

        let formatter = DateFormatter()
        formatter.calendar = configured
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter
    }

    func trackAppOpenedIfNeeded(now: Date = .now) {
        let scope = userScope()
        let day = dayKey(for: now)
        let key = appOpenedPrefix + scope

        if defaults.string(forKey: key) == day {
            return
        }
        defaults.set(day, forKey: key)

        Analytics.track("app_opened", [
            "day": day,
            "authenticated": scope != "anonymous"
        ])
    }

    func trackDailyFocusSnapshotIfNeeded(totalSeconds: TimeInterval,
                                         source: String,
                                         now: Date = .now) {
        let scope = userScope()
        let day = dayKey(for: now)
        let roundedSeconds = max(0, Int(totalSeconds.rounded()))
        let sentKey = dailySnapshotSentPrefix + scope + "." + day
        let lastKey = dailySnapshotLastPrefix + scope + "." + day

        let hasSentToday = defaults.bool(forKey: sentKey)
        let lastSeconds = defaults.object(forKey: lastKey) as? Int ?? -1

        let shouldSend: Bool
        if !hasSentToday {
            shouldSend = true
        } else if source == "focus_stop" {
            shouldSend = roundedSeconds != lastSeconds
        } else {
            shouldSend = roundedSeconds >= lastSeconds + 300
        }

        guard shouldSend else { return }

        defaults.set(true, forKey: sentKey)
        defaults.set(max(lastSeconds, roundedSeconds), forKey: lastKey)

        Analytics.track("daily_focus_snapshot", [
            "day": day,
            "focused_seconds_today": roundedSeconds,
            "focused_hours_today": Double(roundedSeconds) / 3600,
            "source": source,
            "authenticated": scope != "anonymous"
        ])
    }
}

private extension UsageAnalyticsService {
    func dayKey(for date: Date) -> String {
        dayFormatter.string(from: calendar.startOfDay(for: date))
    }

    func userScope() -> String {
        if let userID = defaults.string(forKey: authUserIDKey),
           !userID.isEmpty {
            return userID
        }
        return "anonymous"
    }
}
