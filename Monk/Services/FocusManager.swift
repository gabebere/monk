import Foundation
import SwiftData
import Combine
import UserNotifications
import WidgetKit

@MainActor
final class FocusManager: ObservableObject {
    @Published private(set) var currentSession: FocusSession?
    @Published private(set) var todayTotalSeconds: TimeInterval = 0

    private var timer: AnyCancellable?
    private let modelContext: ModelContext
    private let notificationCenter: UserNotificationCenterType
    private let liveActivityController: LiveActivityControllerType?
    private let calendar: Calendar

    init(modelContext: ModelContext,
         notificationCenter: UserNotificationCenterType = UNUserNotificationCenter.current(),
         liveActivityController: LiveActivityControllerType? = SystemLiveActivityController(),
         calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.modelContext = modelContext
        self.notificationCenter = notificationCenter
        self.liveActivityController = liveActivityController
        self.calendar = calendar
        self.currentSession = fetchInProgressSession()
        recalcTodayTotal()
        startTicking()
        // Optionally purge short sessions on launch if the preference is enabled
        purgeShortSessionsIfNeeded()
        // If a session is active on launch, recreate Live Activity and nudge
        if let s = currentSession {
            liveActivityController?.start(startedAt: s.startedAt)
            scheduleNudgeIfNeeded()
        }
    }

    func start(note: String? = nil, tags: [String] = []) {
        guard currentSession == nil else { return }
        let session = FocusSession(startedAt: Date(), endedAt: nil, note: note, tags: tags)
        modelContext.insert(session)
        try? modelContext.save()
        currentSession = session
        scheduleNudgeIfNeeded()
        Haptics.light()
        // Start Live Activity (if available)
        liveActivityController?.start(startedAt: session.startedAt)
    }

    func stop() {
        guard let session = currentSession else { return }
        session.endedAt = Date()
        try? modelContext.save()
        // Discard session if shorter than threshold and preference is enabled
        if shouldDiscard(session: session) {
            modelContext.delete(session)
            try? modelContext.save()
        }
        currentSession = nil
        cancelNudges()
        recalcTodayTotal()
        Haptics.success()
        // End Live Activity (if available)
        liveActivityController?.end()
    }

    func recalcTodayTotal(now: Date = .now) {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return }

        // Fetch sessions overlapping today (not only those that started today)
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { s in
                s.startedAt < startOfTomorrow && (s.endedAt == nil || s.endedAt! >= startOfToday)
            },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []

        var total: TimeInterval = 0
        for s in sessions {
            let segStart = max(s.startedAt, startOfToday)
            let segEnd = min(s.endedAt ?? now, startOfTomorrow)
            if segEnd > segStart { total += segEnd.timeIntervalSince(segStart) }
        }
        todayTotalSeconds = total
        publishAppGroupSummary(now: now)
    }

    private func fetchInProgressSession() -> FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { s in s.endedAt == nil }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func startTicking() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.currentSession != nil { self.recalcTodayTotal() }
                self.objectWillChange.send() // keep timer updates flowing
            }
    }

    // MARK: - Nudges
    private func scheduleNudgeIfNeeded() {
        guard let prefs = ensurePreferences(), let minutes = prefs.nudgeMinutes else { return }
        notificationCenter.getAuthorizationStatus { status in
            if status == .notDetermined {
                self.notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
            let content = UNMutableNotificationContent()
            content.title = "Time for a quick break?"
            content.body = "You’ve been in deep work for \(minutes) minutes."
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
            let req = UNNotificationRequest(identifier: "nudge", content: content, trigger: trigger)
            self.notificationCenter.add(req, withCompletionHandler: nil)
        }
    }

    private func cancelNudges() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["nudge"])
    }

    @discardableResult
    private func ensurePreferences() -> Preferences? {
        let descriptor = FetchDescriptor<Preferences>()
        if let prefs = try? modelContext.fetch(descriptor).first { return prefs }
        let prefs = Preferences()
        modelContext.insert(prefs)
        try? modelContext.save()
        return prefs
    }
}

// MARK: - App Group summary publishing
extension FocusManager {
    private func publishAppGroupSummary(now: Date = .now) {
        let todayHours = todayTotalSeconds / 3600
        let last7 = lastNDaysTotals(n: 7, now: now)
        AppGroupBridge.writeSummary(todayHours: todayHours, last7: last7)
        // Nudge the widget to refresh its timeline
        WidgetCenter.shared.reloadTimelines(ofKind: "MonkSummaryWidget")
    }

    private func lastNDaysTotals(n: Int, now: Date = .now) -> [Double] {
        guard n > 0 else { return [] }
        let cal = calendar
        let end = cal.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        guard let start = cal.date(byAdding: .day, value: -n, to: end) else { return [] }
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { s in s.startedAt < end && (s.endedAt == nil || s.endedAt! >= start) },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return InsightsAggregator.lastNDaysTotals(sessions: sessions, n: n, now: now, calendar: cal)
    }
}

// MARK: - Short session handling
extension FocusManager {
    private var shortThresholdSeconds: TimeInterval { 120 }

    private func shouldDiscard(session: FocusSession, now: Date = .now) -> Bool {
        let descriptor = FetchDescriptor<Preferences>()
        let prefs = (try? modelContext.fetch(descriptor))?.first
        guard prefs?.discardShortSessions == true else { return false }
        let dur = max(0, (session.endedAt ?? now).timeIntervalSince(session.startedAt))
        return dur < shortThresholdSeconds
    }

    func purgeShortSessionsIfNeeded(now: Date = .now) {
        let descriptor = FetchDescriptor<Preferences>()
        let prefs = (try? modelContext.fetch(descriptor))?.first
        guard prefs?.discardShortSessions == true else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        var didDelete = false
        for s in all {
            guard let end = s.endedAt else { continue }
            let dur = max(0, end.timeIntervalSince(s.startedAt))
            if dur < shortThresholdSeconds {
                modelContext.delete(s)
                didDelete = true
            }
        }
        if didDelete { try? modelContext.save(); recalcTodayTotal(now: now) }
    }
}
