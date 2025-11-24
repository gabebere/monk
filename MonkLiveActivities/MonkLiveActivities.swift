import ActivityKit
import WidgetKit
import SwiftUI

@main
struct MonkLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        FocusSessionLiveActivityWidget()
        WeeklyGoalWidget()
    }
}

struct FocusSessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusSessionActivityAttributes.self) { context in
            FocusLiveActivityLockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    FocusDynamicIslandExpanded(context: context)
                }
            } compactLeading: {
                FocusDynamicIslandCompactLeading(context: context)
            } compactTrailing: {
                FocusDynamicIslandCompactTrailing(context: context)
            } minimal: {
                FocusDynamicIslandMinimal(context: context)
            }
        }
    }
}

// MARK: - Lock Screen presentation

private struct FocusLiveActivityLockScreen: View {
    let context: ActivityViewContext<FocusSessionActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: context.state.timerInterval.lowerBound, by: 1)) { timeline in
            let metrics = FocusLiveMetrics(state: context.state, now: timeline.date)
            ZStack {
                ContainerRelativeShape()
                    .fill(FocusLiveActivityPalette.background)
                ContainerRelativeShape()
                    .fill(FocusLiveActivityPalette.halo)
                    .opacity(0.45)
                FocusLockScreenContent(metrics: metrics)
                    .padding(30)
            }
        }
    }
}

// MARK: - Dynamic Island presentations

private struct FocusDynamicIslandExpanded: View {
    let context: ActivityViewContext<FocusSessionActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: context.state.timerInterval.lowerBound, by: 1)) { timeline in
            let metrics = FocusLiveMetrics(state: context.state, now: timeline.date)
            HStack(spacing: 16) {
                ProjectGoalProgress(metrics: metrics)
                FocusIslandStatusContent(metrics: metrics)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
    }
}

private struct FocusDynamicIslandCompactLeading: View {
    let context: ActivityViewContext<FocusSessionActivityAttributes>
    var body: some View {
        Image(systemName: "target")
            .font(.caption.weight(.semibold))
            .foregroundStyle(FocusLiveActivityPalette.primaryText)
    }
}

private struct FocusDynamicIslandCompactTrailing: View {
    let context: ActivityViewContext<FocusSessionActivityAttributes>
    var body: some View {
        TimelineView(.periodic(from: context.state.timerInterval.lowerBound, by: 1)) { timeline in
            let metrics = FocusLiveMetrics(state: context.state, now: timeline.date)
            Text(metrics.compactTimeRemaining)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(FocusLiveActivityPalette.primaryText)
        }
    }
}

private struct FocusDynamicIslandMinimal: View {
    let context: ActivityViewContext<FocusSessionActivityAttributes>
    var body: some View {
        TimelineView(.periodic(from: context.state.timerInterval.lowerBound, by: 1)) { timeline in
            let metrics = FocusLiveMetrics(state: context.state, now: timeline.date)
            Text(metrics.compactTimeRemaining)
                .font(.caption.weight(.bold))
                .foregroundStyle(FocusLiveActivityPalette.primaryText)
        }
    }
}

// MARK: - Building Blocks

private struct FocusLockScreenContent: View {
    let metrics: FocusLiveMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if metrics.weeklyGoalProgress != nil {
                ProjectGoalProgress(metrics: metrics)
                    .frame(height: 10)
            } else if let progress = metrics.progress {
                FocusActivityProgressBar(progress: progress)
                    .frame(height: 8)
            }
            details
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metrics.statusText)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(FocusLiveActivityPalette.captionText)
                Text(metrics.projectTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FocusLiveActivityPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
            ProjectWeekStats(metrics: metrics, showDetailLine: false)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if metrics.isPaused {
                FocusStatusBadge(label: "Paused")
            }
        }
    }
}

private struct FocusScoreColumn: View {
    let metrics: FocusLiveMetrics
    var decorated: Bool = true

    var body: some View {
        EmptyView()
    }
}

private struct FocusIslandStatusContent: View {
    let metrics: FocusLiveMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(metrics.projectTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FocusLiveActivityPalette.primaryText)
                .lineLimit(1)
            if let progress = metrics.progress {
                FocusActivityProgressBar(progress: progress)
                    .frame(height: 6)
            }
            HStack {
                Text(metrics.primaryTimeValue)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(metrics.secondaryTimeValue)
                    .font(.caption2)
            }
            .foregroundStyle(FocusLiveActivityPalette.captionText)
        }
    }
}

private struct FocusMetricTile: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FocusLiveActivityPalette.captionText)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(FocusLiveActivityPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(FocusLiveActivityPalette.captionText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FocusStatusBadge: View {
    let label: String

    var body: some View {
        Text(label.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.18))
            )
            .foregroundStyle(FocusLiveActivityPalette.primaryText)
    }
}

private struct ProjectGoalProgress: View {
    let metrics: FocusLiveMetrics

    private var fraction: Double {
        metrics.weeklyGoalProgress ?? 0
    }

    private var label: String {
        if let completed = metrics.weekCompletedSeconds, let goal = metrics.weekGoalSeconds {
            return "\(FocusLiveMetrics.formatHours(completed)) / \(FocusLiveMetrics.formatHours(goal))"
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Weekly")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FocusLiveActivityPalette.captionText)
                Spacer()
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FocusLiveActivityPalette.captionText)
            }
            FocusActivityProgressBar(progress: fraction)
                .frame(height: 8)
        }
    }
}

private struct ProjectWeekStats: View {
    let metrics: FocusLiveMetrics
    var showDetailLine: Bool = true

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let goal = metrics.weekGoalSeconds, goal > 0, let completed = metrics.weekCompletedSeconds {
                Text("\(metrics.weeklyPercent)%")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(FocusLiveActivityPalette.primaryText)
                if showDetailLine {
                    Text("\(FocusLiveMetrics.formatHours(completed)) of \(FocusLiveMetrics.formatHours(goal))")
                        .font(.caption2)
                        .foregroundStyle(FocusLiveActivityPalette.captionText)
                }
            } else if let completed = metrics.weekCompletedSeconds {
                Text(FocusLiveMetrics.formatHours(completed))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(FocusLiveActivityPalette.primaryText)
                if showDetailLine {
                    Text("This week")
                        .font(.caption2)
                        .foregroundStyle(FocusLiveActivityPalette.captionText)
                }
            } else {
                Text("No goal")
                    .font(.caption2)
                    .foregroundStyle(FocusLiveActivityPalette.captionText)
            }
        }
    }
}

private struct FocusActivityProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FocusLiveActivityPalette.progressTrack)
                Capsule()
                    .fill(FocusLiveActivityPalette.accent)
                    .frame(width: proxy.size.width * CGFloat(min(max(progress, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Metrics helper

private struct FocusLiveMetrics {
    let projectTitle: String
    let progress: Double?
    let elapsedSeconds: Int
    let weekGoalSeconds: Int?
    let weekCompletedSeconds: Int?
    let weekRemainingSeconds: Int?
    let todayGoalSeconds: Int?
    let todayCompletedSeconds: Int?
    let todayRemainingSeconds: Int?
    let isPaused: Bool

    init(state: FocusSessionActivityAttributes.ContentState, now: Date) {
        projectTitle = state.projectName?.isEmpty == false ? state.projectName! : "Focus Session"
        weekGoalSeconds = state.weeklyGoalSeconds.map { max(0, Int(round($0))) }
        weekCompletedSeconds = state.weeklyCompletedSeconds.map { max(0, Int(round($0))) }
        if let explicit = state.weeklyRemainingSeconds {
            weekRemainingSeconds = max(0, Int(round(explicit)))
        } else if let goal = weekGoalSeconds, let completed = weekCompletedSeconds {
            weekRemainingSeconds = max(0, goal - completed)
        } else {
            weekRemainingSeconds = nil
        }

        let goalSource = state.todayGoalSeconds ?? state.dailyTargetSeconds
        if let goalValue = goalSource {
            todayGoalSeconds = max(0, Int(round(goalValue)))
        } else {
            todayGoalSeconds = nil
        }
        todayCompletedSeconds = state.todayCompletedSeconds.map { max(0, Int(round($0))) }
        if let explicit = state.todayRemainingSeconds {
            todayRemainingSeconds = max(0, Int(round(explicit)))
        } else if let goal = todayGoalSeconds {
            todayRemainingSeconds = max(0, goal - (todayCompletedSeconds ?? 0))
        } else {
            todayRemainingSeconds = nil
        }

        isPaused = state.isPaused

        let start = state.timerInterval.lowerBound
        let effectiveNow = state.isPaused ? state.timerInterval.upperBound : now
        elapsedSeconds = max(0, Int(effectiveNow.timeIntervalSince(start)))

        if let goal = weekGoalSeconds, goal > 0, let completed = weekCompletedSeconds {
            progress = min(max(Double(completed) / Double(goal), 0), 1)
        } else {
            progress = nil
        }
    }

    var statusText: String { isPaused ? "Session Paused" : "Focus Session" }

    var weeklyGoalProgress: Double? {
        guard let goal = weekGoalSeconds, goal > 0, let completed = weekCompletedSeconds else { return nil }
        return min(max(Double(completed) / Double(goal), 0), 1)
    }

    var weeklyPercent: Int {
        guard let fraction = weeklyGoalProgress else { return 0 }
        return Int(round(fraction * 100))
    }

    var timeHeadline: String {
        if weekRemainingSeconds != nil { return "Week Remaining" }
        return "Elapsed"
    }

    var primaryTimeValue: String {
        if let weekRemainingSeconds {
            return FocusLiveMetrics.formatDuration(weekRemainingSeconds)
        }
        return FocusLiveMetrics.formatDuration(elapsedSeconds)
    }

    var secondaryTimeValue: String {
        if let completed = weekCompletedSeconds, let goal = weekGoalSeconds, goal > 0 {
            return "\(FocusLiveMetrics.formatDuration(completed)) of \(FocusLiveMetrics.formatDuration(goal))"
        }
        if let completed = weekCompletedSeconds {
            return "\(FocusLiveMetrics.formatDuration(completed)) logged"
        }
        return "Live \(FocusLiveMetrics.formatShort(elapsedSeconds))"
    }

    var targetHoursText: String? {
        guard let goal = todayGoalSeconds else { return nil }
        let completed = todayCompletedSeconds ?? 0
        return "\(FocusLiveMetrics.formatHours(completed)) / \(FocusLiveMetrics.formatHours(goal))"
    }

    var targetStatusText: String {
        if let remaining = todayRemainingSeconds, remaining > 0 {
            return "\(FocusLiveMetrics.formatDuration(remaining)) to goal"
        }
        if let goal = todayGoalSeconds {
            if goal > 0 {
                return "Today's goal met"
            } else {
                return "Weekly goal met"
            }
        }
        if let completed = todayCompletedSeconds, completed > 0 {
            return "\(FocusLiveMetrics.formatDuration(completed)) logged today"
        }
        return "No focus logged yet"
    }

    var compactTimeRemaining: String {
        if let remaining = todayRemainingSeconds, remaining > 0 {
            return FocusLiveMetrics.formatShort(remaining)
        }
        if let remaining = weekRemainingSeconds {
            return FocusLiveMetrics.formatShort(remaining)
        }
        return FocusLiveMetrics.formatShort(elapsedSeconds)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func formatShort(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes >= 100 { return "\(minutes)m" }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func formatHours(_ seconds: Int) -> String {
        let hours = Double(seconds) / 3600.0
        if seconds == 0 { return "0h" }
        if hours >= 10 { return String(format: "%.0fh", hours) }
        if hours >= 1 { return String(format: "%.1fh", hours) }
        return String(format: "%.0fm", hours * 60)
    }
}

// MARK: - Palette

private enum FocusLiveActivityPalette {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.07, blue: 0.26),
            Color(red: 0.19, green: 0.12, blue: 0.37),
            Color(red: 0.10, green: 0.29, blue: 0.47),
            Color(red: 0.05, green: 0.48, blue: 0.56)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let halo = LinearGradient(
        colors: [
            Color(red: 0.47, green: 0.43, blue: 0.96).opacity(0.35),
            Color.clear
        ],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )

    static let accent = LinearGradient(
        colors: [
            Color(red: 0.47, green: 0.43, blue: 0.96),
            Color(red: 0.24, green: 0.57, blue: 0.98),
            Color(red: 0.12, green: 0.73, blue: 0.84)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let primaryText = Color.white.opacity(0.95)
    static let bodyMuted = Color.white.opacity(0.8)
    static let captionText = Color.white.opacity(0.65)
    static let progressTrack = Color.white.opacity(0.18)
}
