import Foundation
import OSLog
import SwiftData
import UserNotifications

@MainActor
final class FocusNudgeScheduler {
    static let shared = FocusNudgeScheduler()

    private let logger = Logger(subsystem: "com.gbr.Monk", category: "FocusNudgeScheduler")
    private let notificationCenter = UNUserNotificationCenter.current()
    private let calendar: Calendar
    private let dayIDFormatter: DateFormatter

    private let nudgePrefix = "focus.nudge."
    private let summaryPrefix = "focus.summary."
    private let deviceSenderKey = "focus.nudges.deviceEnabled"

    private init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        var configuredCalendar = calendar
        configuredCalendar.locale = .autoupdatingCurrent
        configuredCalendar.timeZone = .autoupdatingCurrent
        self.calendar = configuredCalendar

        let formatter = DateFormatter()
        formatter.calendar = configuredCalendar
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        self.dayIDFormatter = formatter
    }

    func refresh(modelContext: ModelContext,
                 currentSession: FocusSession?,
                 now: Date = .now,
                 reason: String) async {
        let prefs = (try? modelContext.fetch(FetchDescriptor<Preferences>()))?.first
        let nudgesEnabled = prefs?.focusNudgesEnabled ?? true
        let summaryEnabled = prefs?.focusDailySummaryEnabled ?? true
        let deviceEnabled = isSenderEnabledOnThisDevice

        if !deviceEnabled || (!nudgesEnabled && !summaryEnabled) {
            logger.debug(
                "Skipping focus notifications (disabled); reason=\(reason, privacy: .public), device=\(deviceEnabled, privacy: .public), nudges=\(nudgesEnabled, privacy: .public), summary=\(summaryEnabled, privacy: .public)"
            )
            await removeManagedNotifications()
            return
        }

        let settings = await notificationCenter.notificationSettings()
        guard isAuthorized(settings.authorizationStatus) else {
            logger.debug(
                "Skipping focus notifications (auth=\(String(describing: settings.authorizationStatus), privacy: .public)); reason=\(reason, privacy: .public)"
            )
            await removeManagedNotifications()
            return
        }

        await removeManagedNotifications()

        let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        let scheduledNudges = nudgesEnabled
            ? await scheduleDaytimeNudges(sessions: sessions, currentSession: currentSession, now: now)
            : 0
        let scheduledSummaries = summaryEnabled
            ? await scheduleDailySummaries(sessions: sessions, now: now)
            : 0

        logger.debug(
            "Focus notifications refreshed; reason=\(reason, privacy: .public), nudges=\(scheduledNudges, privacy: .public), summaries=\(scheduledSummaries, privacy: .public)"
        )
    }

    func clearAll() {
        Task { [weak self] in
            await self?.removeManagedNotifications()
        }
    }

    private var isSenderEnabledOnThisDevice: Bool {
        UserDefaults.standard.object(forKey: deviceSenderKey) as? Bool ?? true
    }

    private func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func scheduleDaytimeNudges(sessions: [FocusSession],
                                       currentSession: FocusSession?,
                                       now: Date) async -> Int {
        guard currentSession == nil else {
            logger.debug("Skipping nudge scheduling; active session is running.")
            return 0
        }

        let dayStart = calendar.startOfDay(for: now)
        let adaptiveHour = adaptiveFirstNudgeHour(for: dayStart, sessions: sessions, now: now)
        var scheduled = 0

        for slotIndex in 0..<6 {
            let hourOffset = adaptiveHour + (slotIndex * 2)
            guard let slotDate = calendar.date(byAdding: .hour, value: hourOffset, to: dayStart) else { continue }
            guard slotDate > now else { continue }
            guard let windowStart = calendar.date(byAdding: .hour, value: -2, to: slotDate) else { continue }

            let focusedBeforeSlot = focusedSeconds(sessions: sessions, rangeStart: windowStart, rangeEnd: slotDate, now: now)
            guard focusedBeforeSlot == 0 else {
                logger.debug(
                    "Skipping nudge slot=\(slotIndex, privacy: .public) due to focus in prior window (\(Int(focusedBeforeSlot), privacy: .public)s)."
                )
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = FocusNudgeMessageBank.title(for: slotIndex)
            content.body = FocusNudgeMessageBank.message(forSlot: slotIndex, day: dayStart, calendar: calendar)
            content.sound = .default

            let identifier = "\(nudgePrefix)\(dayID(for: dayStart)).\(slotIndex)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents(for: slotDate), repeats: false)
            )

            do {
                try await notificationCenter.add(request)
                scheduled += 1
                logger.debug("Scheduled nudge id=\(identifier, privacy: .public)")
            } catch {
                logger.error("Failed scheduling nudge \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return scheduled
    }

    private func scheduleDailySummaries(sessions: [FocusSession], now: Date) async -> Int {
        let todayStart = calendar.startOfDay(for: now)
        var scheduled = 0

        for dayOffset in 0...1 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: todayStart),
                  let fireDate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: dayStart),
                  fireDate > now else {
                continue
            }

            let rangeStart = fireDate.addingTimeInterval(-86_400)
            let focused = focusedSeconds(sessions: sessions, rangeStart: rangeStart, rangeEnd: fireDate, now: now)
            let insight = summaryInsight(sessions: sessions, rangeStart: rangeStart, rangeEnd: fireDate, now: now)

            let content = UNMutableNotificationContent()
            content.title = "Daily focus summary"
            content.body = "Last 24h: \(durationString(seconds: focused)). \(insight)"
            content.sound = .default

            let identifier = "\(summaryPrefix)\(dayID(for: dayStart))"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents(for: fireDate), repeats: false)
            )

            do {
                try await notificationCenter.add(request)
                scheduled += 1
                logger.debug("Scheduled summary id=\(identifier, privacy: .public)")
            } catch {
                logger.error("Failed scheduling summary \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return scheduled
    }

    private func adaptiveFirstNudgeHour(for dayStart: Date, sessions: [FocusSession], now: Date) -> Int {
        guard let lookbackStart = calendar.date(byAdding: .day, value: -14, to: dayStart) else { return 8 }

        var firstMinuteByDay: [Date: Int] = [:]

        for session in sessions {
            let sessionEnd = session.endedAt ?? now
            if sessionEnd <= lookbackStart || session.startedAt >= dayStart { continue }

            let clippedStart = max(session.startedAt, lookbackStart)
            let clippedEnd = min(sessionEnd, dayStart)
            guard clippedEnd > clippedStart else { continue }

            var cursor = clippedStart
            while cursor < clippedEnd {
                let sessionDayStart = calendar.startOfDay(for: cursor)
                guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: sessionDayStart) else { break }
                let segmentEnd = min(clippedEnd, nextDayStart)

                if segmentEnd > cursor {
                    let minute = minuteOfDay(for: cursor)
                    let existing = firstMinuteByDay[sessionDayStart]
                    firstMinuteByDay[sessionDayStart] = min(existing ?? minute, minute)
                }
                cursor = segmentEnd
            }
        }

        guard firstMinuteByDay.count >= 3 else {
            logger.debug("Adaptive nudge fallback to 8:00 due to limited history (\(firstMinuteByDay.count, privacy: .public) days).")
            return 8
        }

        let allMinutes = firstMinuteByDay.values.map(Double.init)
        let average = allMinutes.reduce(0, +) / Double(max(1, allMinutes.count))
        let clamped = min(max(average, 8 * 60), 9 * 60)
        let hour = clamped >= (8.5 * 60) ? 9 : 8

        logger.debug("Adaptive nudge hour resolved to \(hour, privacy: .public) from avg minute \(Int(average), privacy: .public).")
        return hour
    }

    private func summaryInsight(sessions: [FocusSession],
                                rangeStart: Date,
                                rangeEnd: Date,
                                now: Date) -> String {
        var totals: [Daypart: TimeInterval] = [:]
        Daypart.allCases.forEach { totals[$0] = 0 }

        for session in sessions {
            let sessionEnd = session.endedAt ?? now
            let clippedStart = max(session.startedAt, rangeStart)
            let clippedEnd = min(sessionEnd, rangeEnd)
            guard clippedEnd > clippedStart else { continue }

            var cursor = clippedStart
            while cursor < clippedEnd {
                let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
                guard let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { break }
                let segmentEnd = min(clippedEnd, nextHour)
                let seconds = segmentEnd.timeIntervalSince(cursor)
                let hour = calendar.component(.hour, from: hourStart)
                let daypart = Daypart(hour: hour)
                totals[daypart, default: 0] += seconds
                cursor = segmentEnd
            }
        }

        guard let dominant = totals.max(by: { $0.value < $1.value }),
              dominant.value > 0 else {
            return "No focus was logged in this window yet."
        }

        return "Most of your focus landed in the \(dominant.key.label)."
    }

    private func focusedSeconds(sessions: [FocusSession],
                                rangeStart: Date,
                                rangeEnd: Date,
                                now: Date) -> TimeInterval {
        guard rangeEnd > rangeStart else { return 0 }

        return sessions.reduce(0) { partial, session in
            let sessionEnd = session.endedAt ?? now
            let clippedStart = max(session.startedAt, rangeStart)
            let clippedEnd = min(sessionEnd, rangeEnd)
            guard clippedEnd > clippedStart else { return partial }
            return partial + clippedEnd.timeIntervalSince(clippedStart)
        }
    }

    private func minuteOfDay(for date: Date) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func dayID(for date: Date) -> String {
        dayIDFormatter.string(from: date)
    }

    private func triggerComponents(for date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private func durationString(seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds.rounded(.down)) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func removeManagedNotifications() async {
        let pendingRequests = await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
        let pendingIDs = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(nudgePrefix) || $0.hasPrefix(summaryPrefix) }

        if !pendingIDs.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }

        let deliveredNotifications = await withCheckedContinuation { continuation in
            notificationCenter.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
        let deliveredIDs = deliveredNotifications
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(nudgePrefix) || $0.hasPrefix(summaryPrefix) }

        if !deliveredIDs.isEmpty {
            notificationCenter.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }
}

private enum Daypart: CaseIterable {
    case morning
    case afternoon
    case evening
    case night

    init(hour: Int) {
        switch hour {
        case 5..<12:
            self = .morning
        case 12..<17:
            self = .afternoon
        case 17..<21:
            self = .evening
        default:
            self = .night
        }
    }

    var label: String {
        switch self {
        case .morning: return "morning"
        case .afternoon: return "afternoon"
        case .evening: return "evening"
        case .night: return "night"
        }
    }
}
