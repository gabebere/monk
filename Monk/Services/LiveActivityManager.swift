import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
enum LiveActivityManager {
    private static var current: Activity<FocusAttributes>?

    static func start(startedAt: Date = .now) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = FocusAttributes()
        let state = FocusAttributes.ContentState(startedAt: startedAt)
        do {
            current = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
        } catch {
            // Silently ignore in internal builds
        }
    }

    static func end() {
        guard let current else { return }
        Task { await current.end(dismissalPolicy: .immediate) }
        Self.current = nil
    }
}
#endif
