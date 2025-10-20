#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<FocusSessionActivityAttributes>?

    private init() {}

    func startActivity(for session: FocusSession) {
        guard LiveActivityManager.activitiesAvailable else { return }
        endActivity()
        let attributes = FocusSessionActivityAttributes(sessionID: session.id)
        let state = makeState(for: session)
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

    func updateActivity(for session: FocusSession) {
        guard LiveActivityManager.activitiesAvailable,
              let activity = currentActivity else { return }
        let state = makeState(for: session)
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
    }

    func endActivity(for session: FocusSession) {
        guard currentActivity?.attributes.sessionID == session.id else { return }
        endActivity()
    }

    private func makeState(for session: FocusSession) -> FocusSessionActivityAttributes.ContentState {
        let isPaused = session.endedAt != nil
        let now = Date()
        let timerEnd = session.endedAt ?? now
        return FocusSessionActivityAttributes.ContentState(
            title: session.project?.title,
            startedAt: session.startedAt,
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
