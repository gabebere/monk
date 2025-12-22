#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.2, macOS 13.1, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<FocusSessionActivityAttributes>?
    private var cachedSnapshot: FocusScoreSnapshot?

    private init() {}

    func startActivity(for session: FocusSession, focusSnapshot: FocusScoreSnapshot?) {
        guard LiveActivityManager.activitiesAvailable else { return }
        endActivity()
        let attributes = FocusSessionActivityAttributes(sessionID: session.id)
        cachedSnapshot = focusSnapshot
        let state = makeState(for: session, snapshot: cachedSnapshot)
        do {
            let content = ActivityContent(state: state, staleDate: nil)
            currentActivity = try Activity<FocusSessionActivityAttributes>.request(
                attributes: attributes,
                content: content
            )
        } catch {
            print("Failed to start live activity: \(error)")
        }
    }

    func updateActivity(for session: FocusSession, focusSnapshot: FocusScoreSnapshot?) {
        guard LiveActivityManager.activitiesAvailable,
              let activity = currentActivity else { return }
        if let focusSnapshot { cachedSnapshot = focusSnapshot }
        let state = makeState(for: session, snapshot: cachedSnapshot)
        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        cachedSnapshot = nil
    }

    func endActivity(for session: FocusSession) {
        guard currentActivity?.attributes.sessionID == session.id else { return }
        endActivity()
    }

    private func makeState(for session: FocusSession, snapshot: FocusScoreSnapshot?, now: Date = .now) -> FocusSessionActivityAttributes.ContentState {
        let isPaused = session.endedAt != nil
        let timerEnd = session.endedAt ?? now
        let project = session.project
        let goalSeconds = project?.weeklyGoalHours.map { max(0, $0) * 3600 }

        let weeklyCompletedSeconds: TimeInterval? = {
            guard let sessions = project?.sessions else { return nil }
            let (weekStart, weekEnd) = weekBounds(containing: now)
            var total: TimeInterval = 0
            for s in sessions {
                let start = s.startedAt
                let end = s.endedAt ?? now
                if end <= weekStart || start >= weekEnd { continue }
                let clippedStart = max(start, weekStart)
                let clippedEnd = min(end, weekEnd)
                if clippedEnd > clippedStart {
                    total += clippedEnd.timeIntervalSince(clippedStart)
                }
            }
            return total
        }()

        return FocusSessionActivityAttributes.ContentState(
            projectName: session.project?.title,
            weeklyGoalSeconds: goalSeconds,
            weeklyCompletedSeconds: weeklyCompletedSeconds,
            weeklyRemainingSeconds: {
                if let goal = goalSeconds, let completed = weeklyCompletedSeconds {
                    return max(0, goal - completed)
                }
                return nil
            }(),
            dailyTargetSeconds: nil,
            todayGoalSeconds: nil,
            todayCompletedSeconds: nil,
            todayRemainingSeconds: nil,
            timerInterval: session.startedAt...timerEnd,
            isPaused: isPaused
        )
    }

    private func weekBounds(containing date: Date) -> (Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        let startOfDay = calendar.startOfDay(for: date)
        let interval = calendar.dateInterval(of: .weekOfYear, for: startOfDay)
        let start = interval?.start ?? startOfDay
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? startOfDay
        return (start, end)
    }

    private static var activitiesAvailable: Bool {
        if #available(iOS 16.2, macOS 13.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }
}
#endif
