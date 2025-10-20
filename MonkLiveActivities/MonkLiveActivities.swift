import ActivityKit
import WidgetKit
import SwiftUI

@main
struct MonkLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        FocusSessionLiveActivityWidget()
    }
}

struct FocusSessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusSessionActivityAttributes.self) { context in
            FocusLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    FocusLiveActivityView(context: context)
                }
            } compactLeading: {
                FocusLiveActivityView.ShortDurationView(context: context)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                FocusLiveActivityView.ShortDurationView(context: context)
            }
        }
    }
}

private struct FocusLiveActivityView: View {
    let context: ActivityViewContext<FocusSessionActivityAttributes>
    @Environment(\.isLuminanceReduced) private var isDimmed

    private var projectName: String {
        let trimmed = context.state.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "this session" : trimmed
    }

    private var backgroundStyle: AnyShapeStyle {
        isDimmed ? AnyShapeStyle(Color.black.opacity(0.6)) : AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.27, green: 0.56, blue: 0.99),
                Color(red: 0.60, green: 0.28, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        TimelineView(.periodic(from: context.state.timerInterval.lowerBound, by: 1)) { timeline in
            let seconds = elapsedSeconds(at: timeline.date)
            VStack(alignment: .leading, spacing: 12) {
                Text("Focused on \(projectName) for \(formattedFullDuration(seconds: seconds))")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundStyle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(borderGradient.opacity(isDimmed ? 0.35 : 0.65), lineWidth: 3)
                            .padding(0.5)
                    )
            )
        }
    }

    private func elapsedSeconds(at now: Date) -> Int {
        let start = context.state.timerInterval.lowerBound
        let upper = context.state.isPaused ? context.state.timerInterval.upperBound : now
        let total = max(0, upper.timeIntervalSince(start))
        return Int(total.rounded())
    }

    private func formattedFullDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) " + (hours == 1 ? "hour" : "hours"))
        }
        if minutes > 0 || hours > 0 {
            parts.append("\(minutes) " + (minutes == 1 ? "minute" : "minutes"))
        }
        parts.append("\(secs) " + (secs == 1 ? "second" : "seconds"))

        guard parts.count > 1 else { return parts[0] }
        let last = parts.removeLast()
        return parts.joined(separator: ", ") + " and " + last
    }

    private static func formattedShortDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%01d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func elapsedSecondsStatic(at now: Date, state: FocusSessionActivityAttributes.ContentState) -> Int {
        let start = state.timerInterval.lowerBound
        let upper = state.isPaused ? state.timerInterval.upperBound : now
        let total = max(0, upper.timeIntervalSince(start))
        return Int(total.rounded())
    }

    struct ShortDurationView: View {
        let context: ActivityViewContext<FocusSessionActivityAttributes>
        var body: some View {
            TimelineView(.periodic(from: context.state.timerInterval.lowerBound, by: 1)) { timeline in
                let seconds = FocusLiveActivityView.elapsedSecondsStatic(at: timeline.date, state: context.state)
                Text(FocusLiveActivityView.formattedShortDuration(seconds: seconds))
                    .font(.system(.caption, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}
