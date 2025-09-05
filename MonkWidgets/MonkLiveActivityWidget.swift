import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct MonkLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { context in
            // Lock Screen/Minimal view
            LiveActivityLockScreenView(startedAt: context.state.startedAt)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    LiveActivityLockScreenView(startedAt: context.state.startedAt)
                }
            } compactLeading: {
                ElapsedText(startedAt: context.state.startedAt)
                    .font(.system(.caption2, design: .monospaced))
            } compactTrailing: {
                Image(systemName: "timer")
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityLockScreenView: View {
    let startedAt: Date
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
            ElapsedText(startedAt: startedAt)
                .font(.system(.headline, design: .monospaced))
                .bold()
        }
        .padding(.vertical, 4)
    }
}

@available(iOS 16.1, *)
private struct ElapsedText: View {
    let startedAt: Date
    @State private var now: Date = .now
    var body: some View {
        Text(timeString)
            .monospacedDigit()
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }
    private var timeString: String {
        let elapsed = now.timeIntervalSince(startedAt)
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
#endif

