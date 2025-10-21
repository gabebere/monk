#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.2, *)
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
        let weeklyProjection = snapshot?.weeklyProjection
        let dynamicTodayGoalHours = snapshot?.dynamicTodayGoalHours
        let todayActualHours = snapshot?.todayActualHours ?? 0

        return FocusSessionActivityAttributes.ContentState(
            projectName: session.project?.title,
            focusScore: snapshot?.score,
            focusScoreDelta: snapshot?.delta,
            focusScoreLabel: snapshot?.rating.rawValue,
            weeklyGoalSeconds: weeklyProjection.map { $0.goalHours * 3600 },
            weeklyCompletedSeconds: weeklyProjection.map { $0.actualHours * 3600 },
            weeklyRemainingSeconds: weeklyProjection.map { $0.remainingHours * 3600 },
            dailyTargetSeconds: snapshot.map { $0.dailyTargetHours * 3600 },
            todayGoalSeconds: dynamicTodayGoalHours.map { max(0, $0) * 3600 },
            todayCompletedSeconds: snapshot.map { $0.todayActualHours * 3600 },
            todayRemainingSeconds: dynamicTodayGoalHours.map { goal in
                max(0, goal - todayActualHours) * 3600
            },
            timerInterval: session.startedAt...timerEnd,
            isPaused: isPaused
        )
    }

    private static var activitiesAvailable: Bool {
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }
}
#endif
