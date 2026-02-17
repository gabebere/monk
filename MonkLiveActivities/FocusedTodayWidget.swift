import WidgetKit
import SwiftUI

struct FocusedTodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: LiveSnapshot
}

struct FocusedTodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusedTodayWidgetEntry {
        FocusedTodayWidgetEntry(date: .now, snapshot: .widgetPlaceholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusedTodayWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? LiveSnapshot.widgetPlaceholder : SnapshotReader.load()
        completion(FocusedTodayWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusedTodayWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotReader.load()

        let entries: [FocusedTodayWidgetEntry]
        if snapshot.timerState == .running {
            entries = (0..<61).compactMap { minuteOffset in
                guard let date = Calendar(identifier: .gregorian).date(byAdding: .minute, value: minuteOffset, to: now) else { return nil }
                return FocusedTodayWidgetEntry(date: date, snapshot: snapshot)
            }
        } else {
            entries = [FocusedTodayWidgetEntry(date: now, snapshot: snapshot)]
        }

        let refreshDate = entries.last?.date.addingTimeInterval(60) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }
}

struct FocusedTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusedTodayWidget", provider: FocusedTodayWidgetProvider()) { entry in
            FocusedTodayWidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .configurationDisplayName("Focused Today")
        .description("Quick focus feedback for today, plus your best focus window.")
    }
}

private struct FocusedTodayWidgetView: View {
    let entry: FocusedTodayWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var now: Date { entry.date }

    private var focusedTodaySeconds: TimeInterval {
        let base = max(0, entry.snapshot.focusedTodaySeconds ?? 0)
        guard entry.snapshot.timerState == .running,
              let timerStart = entry.snapshot.timerStart else {
            return base
        }

        let calendar = Calendar(identifier: .gregorian)
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now

        if timerStart >= tomorrowStart {
            return base
        }

        let deltaStart = max(entry.snapshot.lastUpdatedAt, max(timerStart, todayStart))
        let deltaEnd = min(now, tomorrowStart)
        guard deltaEnd > deltaStart else { return base }
        return base + deltaEnd.timeIntervalSince(deltaStart)
    }

    private var focusedTodayText: String {
        if focusedTodaySeconds < 3600 {
            let minutes = Int((focusedTodaySeconds / 60).rounded())
            return "\(max(0, minutes)) min"
        }
        return String(format: "%.1f h", focusedTodaySeconds / 3600)
    }

    private var bestWindowText: String {
        guard let start = entry.snapshot.calmLaneStartHour,
              let end = entry.snapshot.calmLaneEndHour else {
            return "Best focus window building"
        }
        return String(format: "Best focus window %02d-%02d", max(0, start), max(0, end))
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.24, blue: 0.52),
                Color(red: 0.10, green: 0.34, blue: 0.43)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let outerPadding = max(14, width * 0.085)
            let titleSize = min(max(17, width * 0.09), 24)
            let valueSize = min(max(36, width * 0.21), 58)
            let chipSize = min(max(11, width * 0.055), 15)

            ZStack {
                Text(focusedTodayText)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Focused today")
                        .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)

                    Text(bestWindowText)
                        .font(.system(size: chipSize, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(.horizontal, width * 0.048)
                        .padding(.vertical, height * 0.017)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(outerPadding)
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .containerBackground(for: .widget) {
            background
        }
        .widgetURL(URL(string: "monk://insights"))
        .applyWidgetRenderingMode(renderingMode)
    }
}

private extension View {
    @ViewBuilder
    func applyWidgetRenderingMode(_ mode: WidgetRenderingMode) -> some View {
        if mode == .accented {
            self.widgetAccentable()
        } else {
            self
        }
    }
}

private extension LiveSnapshot {
    static let widgetPlaceholder: LiveSnapshot = {
        LiveSnapshot(
            sessionID: nil,
            taskTitle: nil,
            projectTitle: "Monk",
            timerState: .idle,
            timerStart: nil,
            timerEnd: nil,
            elapsedSeconds: 0,
            weeklyGoalSeconds: nil,
            weeklyCompletedSeconds: nil,
            weeklyRemainingSeconds: nil,
            todayGoalSeconds: nil,
            todayCompletedSeconds: nil,
            todayRemainingSeconds: nil,
            projectGoals: nil,
            focusedTodaySeconds: 52 * 60,
            calmLaneStartHour: 9,
            calmLaneEndHour: 11,
            lastUpdatedAt: .now
        )
    }()
}

#Preview(as: .systemSmall, widget: {
    FocusedTodayWidget()
}, timeline: {
    FocusedTodayWidgetEntry(date: .now, snapshot: .widgetPlaceholder)
})
