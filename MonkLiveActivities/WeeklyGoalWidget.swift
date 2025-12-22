import WidgetKit
import SwiftUI
import SwiftData
import UIKit
import MonkShared

struct WeeklyGoalWidgetEntry: TimelineEntry {
    let date: Date
    let summary: WeeklyProjectGoalSummary?
    let rotation: Int
}

struct WeeklyGoalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyGoalWidgetEntry {
        WeeklyGoalWidgetEntry(date: .now, summary: .placeholder, rotation: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalWidgetEntry) -> Void) {
        let now = Date()
        let capacity = WeeklyGoalWidgetLayout.maxRows(for: context.family)
        let summary = context.isPreview ? .preview : WeeklyGoalWidgetDataSource.loadSummary(now: now)
        let rotationEnabled = (summary?.segments.count ?? 0) > capacity
        let entry = WeeklyGoalWidgetEntry(date: now, summary: summary, rotation: rotationEnabled ? 0 : 0)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalWidgetEntry>) -> Void) {
        let now = Date()
        let summary = WeeklyGoalWidgetDataSource.loadSummary(now: now)
        let capacity = WeeklyGoalWidgetLayout.maxRows(for: context.family)
        let shouldRotate = (summary?.segments.count ?? 0) > capacity
        let entries: [WeeklyGoalWidgetEntry]
        if let summary {
            if shouldRotate {
                let steps = max(summary.segments.count, capacity) * 3 // cadence multiplier; actual interval below
                entries = (0..<steps).map { idx in
                    WeeklyGoalWidgetEntry(date: now.addingTimeInterval(Double(idx) * 5), summary: summary, rotation: idx)
                }
            } else {
                entries = [WeeklyGoalWidgetEntry(date: now, summary: summary, rotation: 0)]
            }
        } else {
            entries = [WeeklyGoalWidgetEntry(date: now, summary: nil, rotation: 0)]
        }
        let refreshDate = entries.last?.date.addingTimeInterval(5) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }
}

struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeeklyGoalWidget", provider: WeeklyGoalWidgetProvider()) { entry in
            WeeklyGoalWidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .configurationDisplayName("Project Goals")
        .description("See a color-coded breakdown of your weekly project goals.")
    }
}

private struct WeeklyGoalWidgetView: View {
    let entry: WeeklyGoalWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let metrics = WeeklyGoalWidgetLayout.metrics(for: family)
        ZStack(alignment: .topLeading) {
            Group {
                if let summary = entry.summary {
                    ProjectGoalsWidgetContent(summary: summary, family: family, layout: metrics, rotation: entry.rotation)
                } else {
                    WeeklyGoalPlaceholderView(family: family, layout: metrics)
                }
            }
            .padding(.horizontal, metrics.outerPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .containerBackground(for: .widget) { WeeklyGoalWidgetPalette.baseBackground }
    }
}

private struct WeeklyGoalWidgetLayout {
    let outerPadding: CGFloat
    let verticalPadding: CGFloat
    let sectionSpacing: CGFloat
    let headerSpacing: CGFloat
    let legendSpacing: CGFloat
    let progressHeight: CGFloat

    static func metrics(for family: WidgetFamily) -> WeeklyGoalWidgetLayout {
        switch family {
        case .systemSmall:
            return WeeklyGoalWidgetLayout(
                outerPadding: 10,
                verticalPadding: 8,
                sectionSpacing: 6,
                headerSpacing: 4,
                legendSpacing: 5,
                progressHeight: 9
            )
        case .systemMedium:
            return WeeklyGoalWidgetLayout(
                outerPadding: 14,
                verticalPadding: 8,
                sectionSpacing: 6,
                headerSpacing: 4,
                legendSpacing: 6,
                progressHeight: 9
            )
        case .systemLarge:
            return WeeklyGoalWidgetLayout(
                outerPadding: 20,
                verticalPadding: 14,
                sectionSpacing: 14,
                headerSpacing: 8,
                legendSpacing: 10,
                progressHeight: 14
            )
        default:
            return WeeklyGoalWidgetLayout(
                outerPadding: 18,
                verticalPadding: 12,
                sectionSpacing: 12,
                headerSpacing: 8,
                legendSpacing: 8,
                progressHeight: 12
            )
        }
    }

    static func maxRows(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 2
        case .systemMedium:
            return 2
        case .systemLarge:
            return 4
        default:
            return 2
        }
    }
}

private struct ProjectGoalsWidgetContent: View {
    let summary: WeeklyProjectGoalSummary
    let family: WidgetFamily
    let layout: WeeklyGoalWidgetLayout
    let rotation: Int
    private let capHours: Double = 112
    private var maxRows: Int { WeeklyGoalWidgetLayout.maxRows(for: family) }
    private var totalLabel: String { "\(hoursLabel(summary.totalActualHours))h of \(hoursLabel(summary.totalGoalHours))h" }
    private var isSmall: Bool { family == .systemSmall }
    private var isMedium: Bool { family == .systemMedium }

    private var normalizedSegments: [WidgetGoalSegment] {
        let total = max(summary.totalGoalHours, 1)
        var cursor: Double = 0
        return summary.segments
            .sorted { $0.goalHours > $1.goalHours }
            .compactMap { segment in
                let scaledGoal = segment.goalHours * summary.scaleFactor
                guard scaledGoal > 0 else { return nil }
                let goalFraction = min(max(scaledGoal / total, 0), 1)
                let progress = segment.goalHours > 0 ? min(max(segment.actualHours / segment.goalHours, 0), 1) : 0
                defer { cursor += goalFraction }
                return WidgetGoalSegment(
                    id: segment.id,
                    title: segment.title,
                    gradientIndex: segment.gradientIndex,
                    startFraction: cursor,
                    goalFraction: goalFraction,
                    fillFraction: goalFraction * progress,
                    goalHours: segment.goalHours,
                    actualHours: segment.actualHours
                )
            }
    }

    private var rotatingRows: [WidgetSmallRow] {
        guard !normalizedSegments.isEmpty else { return [] }
        let count = normalizedSegments.count
        let limited = normalizedSegments.sorted { $0.goalHours > $1.goalHours }
        if count <= maxRows {
            return limited.prefix(maxRows).map { row(for: $0) }
        }
        let start = rotation % max(1, count)
        let reordered = (0..<count).map { idx in
            limited[(start + idx) % count]
        }
        return reordered
            .prefix(maxRows)
            .map { row(for: $0) }
    }

    private func row(for segment: WidgetGoalSegment) -> WidgetSmallRow {
        let progress = segment.goalHours > 0 ? min(max(segment.actualHours / segment.goalHours, 0), 1) : 0
        return WidgetSmallRow(
            id: segment.id,
            title: segment.title,
            gradientIndex: segment.gradientIndex,
            progress: progress,
            goalHours: segment.goalHours,
            actualHours: segment.actualHours
        )
    }

    private var completionPercent: Int {
        guard summary.totalGoalHours > 0 else { return 0 }
        return Int(round(min(max(summary.totalActualHours / summary.totalGoalHours, 0), 1) * 100))
    }

    private var remainingText: String {
        if summary.rawGoalHours > capHours {
            return "Capped at \(Int(capHours))h"
        }
        let remaining = max(0, capHours - summary.rawGoalHours)
        return "\(Int(remaining))h free"
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                smallLayout
            } else if family == .systemMedium {
                mediumLayout
            } else {
                regularLayout
            }
        }
    }

    private var regularLayout: some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            header(percentSize: regularPercentSize)
            WidgetGoalBar(segments: normalizedSegments)
                .frame(height: layout.progressHeight)
            WidgetProjectRows(rows: rotatingRows, spacing: layout.legendSpacing)
            footerLine
        }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            header(percentSize: regularPercentSize)
            WidgetProjectRows(rows: rotatingRows, spacing: layout.legendSpacing)
            footerLine
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            header(percentSize: 0, hidePercent: true, compactSubtitle: true, hidePlanLine: true)
            if rotatingRows.isEmpty {
                Text("Set weekly goals on projects to see them here.")
                    .font(.caption2)
                    .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
            } else {
                WidgetProjectRows(rows: rotatingRows, spacing: 6)
                footerLine
            }
        }
    }

    private var footerLine: some View {
        HStack {
            Text(remainingText)
                .font(.caption2)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
            Spacer()
        }
    }

    private func header(percentSize: CGFloat, hidePercent: Bool = false, compactSubtitle: Bool = false, hidePlanLine: Bool = false) -> some View {
        let inlineSubtitle = isMedium && !isSmall && !compactSubtitle

        return HStack(alignment: .firstTextBaseline, spacing: layout.headerSpacing) {
            VStack(alignment: .leading, spacing: inlineSubtitle ? 0 : 2) {
                if inlineSubtitle {
                    HStack(spacing: 6) {
                        Text("Project Goals")
                            .font(headerTitleFont)
                            .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !hidePlanLine {
                            Text(totalLabel)
                                .font(headerSubtitleFont)
                                .foregroundStyle(WeeklyGoalWidgetPalette.titleSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                } else {
                    Text("Project Goals")
                        .font(headerTitleFont)
                        .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !hidePlanLine {
                        Text(totalLabel)
                            .font(compactSubtitle ? headerSubtitleFontSmall : headerSubtitleFont)
                            .foregroundStyle(WeeklyGoalWidgetPalette.titleSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            Spacer()
            if !hidePercent {
                Text("\(completionPercent)%")
                    .font(.system(size: percentSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var headerTitleFont: Font {
        if isSmall { return .headline.weight(.semibold) }
        if isMedium { return .headline.weight(.semibold) }
        return .headline.weight(.semibold)
    }

    private var headerSubtitleFont: Font {
        if isSmall { return .caption.weight(.medium) }
        if isMedium { return .footnote.weight(.medium) }
        return .subheadline.weight(.medium)
    }

    private var headerSubtitleFontSmall: Font {
        if isSmall { return .caption2.weight(.medium) }
        if isMedium { return .caption.weight(.medium) }
        return .footnote.weight(.medium)
    }

    private var regularPercentSize: CGFloat {
        switch family {
        case .systemSmall: return 20
        case .systemMedium: return 22
        case .systemLarge: return 32
        default: return 22
        }
    }

}

private struct WidgetGoalSegment: Identifiable {
    let id: UUID
    let title: String
    let gradientIndex: Int
    let startFraction: Double
    let goalFraction: Double
    let fillFraction: Double
    let goalHours: Double
    let actualHours: Double

    var progressPercent: Int {
        guard goalHours > 0 else { return 0 }
        return Int(round(min(max(actualHours / goalHours, 0), 1) * 100))
    }
}

private struct WidgetGoalBar: View {
    let segments: [WidgetGoalSegment]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(WeeklyGoalWidgetPalette.progressTrack)
                ForEach(segments) { segment in
                    let gradient = WidgetProjectPalette.gradient(at: segment.gradientIndex)
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(LinearGradient(colors: [gradient.start.opacity(0.35), gradient.end.opacity(0.28)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width * segment.goalFraction)
                        .offset(x: width * segment.startFraction)
                }
                ForEach(segments) { segment in
                    let gradient = WidgetProjectPalette.gradient(at: segment.gradientIndex)
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(LinearGradient(colors: [gradient.start, gradient.end], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width * segment.fillFraction)
                        .offset(x: width * segment.startFraction)
                }
            }
        }
    }
}

private struct WidgetProjectRows: View {
    let rows: [WidgetSmallRow]
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows) { row in
                WidgetProjectRow(row: row)
            }
        }
    }
}

private struct WidgetSmallRow: Identifiable {
    let id: UUID
    let title: String
    let gradientIndex: Int
    let progress: Double
    let goalHours: Double
    let actualHours: Double

    var percentString: String {
        "\(Int(round(min(max(progress, 0), 1) * 100)))%"
    }

    var progressClamped: Double {
        min(max(progress, 0), 1)
    }
}

private struct WidgetProjectRow: View {
    let row: WidgetSmallRow

    var body: some View {
        let gradient = WidgetProjectPalette.gradient(at: row.gradientIndex)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Spacer()
                Text(row.percentString)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titleSecondary)
            }
            Text("\(hoursLabel(row.actualHours))h of \(hoursLabel(row.goalHours))h")
                .font(.caption2)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(WeeklyGoalWidgetPalette.progressTrack)
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(LinearGradient(colors: [gradient.start, gradient.end], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width * row.progressClamped)
                }
            }
            .frame(height: 7)
        }
    }
}

private func hoursLabel(_ value: Double) -> String {
    let rounded = value.rounded()
    if abs(rounded - value) < 0.01 {
        return String(format: "%.0f", rounded)
    }
    return String(format: "%.1f", value)
}

private struct WeeklyGoalPlaceholderView: View {
    let family: WidgetFamily
    let layout: WeeklyGoalWidgetLayout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            Text("Project Goals")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
            WidgetGoalBar(segments: placeholderSegments)
                .frame(height: layout.progressHeight)
            Text("Set weekly goals on projects to see them here.")
                .font(.caption)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
        }
    }

    private var placeholderSegments: [WidgetGoalSegment] {
        [
            WidgetGoalSegment(id: UUID(), title: "Research", gradientIndex: 0, startFraction: 0, goalFraction: 0.35, fillFraction: 0.22, goalHours: 40, actualHours: 14),
            WidgetGoalSegment(id: UUID(), title: "Writing", gradientIndex: 1, startFraction: 0.35, goalFraction: 0.28, fillFraction: 0.16, goalHours: 32, actualHours: 9),
            WidgetGoalSegment(id: UUID(), title: "Planning", gradientIndex: 2, startFraction: 0.63, goalFraction: 0.22, fillFraction: 0.18, goalHours: 25, actualHours: 14)
        ]
    }
}

private enum WeeklyGoalWidgetPalette {
    static let baseBackground = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.07, blue: 0.26),
            Color(red: 0.19, green: 0.12, blue: 0.38),
            Color(red: 0.08, green: 0.36, blue: 0.58),
            Color(red: 0.05, green: 0.58, blue: 0.62)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let titlePrimary = Color.white.opacity(0.95)
    static let titleSecondary = Color.white.opacity(0.78)
    static let bodyMuted = Color.white.opacity(0.72)
    static let accentHigh = Color(red: 0.18, green: 0.86, blue: 0.94)
    static let progressTrack = Color.white.opacity(0.16)
}

private enum WeeklyGoalWidgetDataSource {
    static func loadSummary(now: Date) -> WeeklyProjectGoalSummary? {
        do {
            let schema = Schema([FocusSession.self, Preferences.self, Project.self])
            let configuration = ModelConfiguration(cloudKitDatabase: .private("iCloud.com.gbr.Monk"))
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)

            let projects = try context.fetch(FetchDescriptor<Project>())
            guard !projects.isEmpty else { return nil }

            let calendar = Calendar(identifier: .gregorian)
            let startDate = calendar.date(byAdding: .day, value: -21, to: now) ?? now.addingTimeInterval(-21 * 24 * 3600)

            let descriptor = FetchDescriptor<FocusSession>(
                predicate: #Predicate { session in
                    session.startedAt >= startDate
                },
                sortBy: [SortDescriptor(\FocusSession.startedAt, order: .forward)]
            )

            let sessions = try context.fetch(descriptor)
            let analyzer = InsightsAnalyzer()
            let summary = analyzer.weeklyProjectGoals(projects: projects, sessions: sessions, now: now)
            return summary.hasGoals ? summary : nil
        } catch {
            return nil
        }
    }
}

private enum WidgetProjectPalette {
    private static let gradients: [(start: Color, end: Color)] = [
        (Color(red: 0.27, green: 0.56, blue: 0.99), Color(red: 0.60, green: 0.28, blue: 0.98)),
        (Color(red: 0.33, green: 0.76, blue: 0.86), Color(red: 0.20, green: 0.48, blue: 0.97)),
        (Color(red: 0.99, green: 0.62, blue: 0.45), Color(red: 0.95, green: 0.30, blue: 0.55)),
        (Color(red: 0.98, green: 0.80, blue: 0.36), Color(red: 0.96, green: 0.48, blue: 0.31)),
        (Color(red: 0.54, green: 0.43, blue: 0.99), Color(red: 0.28, green: 0.21, blue: 0.58)),
        (Color(red: 0.34, green: 0.64, blue: 0.99), Color(red: 0.22, green: 0.30, blue: 0.64)),
        (Color(red: 0.99, green: 0.45, blue: 0.69), Color(red: 0.58, green: 0.32, blue: 0.93)),
        (Color(red: 0.46, green: 0.35, blue: 0.82), Color(red: 0.19, green: 0.18, blue: 0.38))
    ]

    static func gradient(at index: Int) -> (start: Color, end: Color) {
        precondition(!gradients.isEmpty)
        if index < gradients.count { return gradients[index] }
        let base = gradients[index % gradients.count]
        let cycle = max(1, index / gradients.count)
        let lighten = min(0.10, 0.04 * Double(cycle))
        let darken = min(0.15, 0.05 * Double(cycle))
        return (adjust(base.start, brightnessDelta: lighten), adjust(base.end, brightnessDelta: -darken))
    }

    private static func adjust(_ color: Color, brightnessDelta: Double) -> Color {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let adjusted = max(0.0, min(1.0, brightness + brightnessDelta))
            return Color(hue: hue, saturation: saturation, brightness: adjusted, opacity: alpha)
        }
        return color
    }
}

private extension WeeklyProjectGoalSummary {
    static let placeholder: WeeklyProjectGoalSummary = .mock()
    static let preview: WeeklyProjectGoalSummary = .mock()

    static func mock() -> WeeklyProjectGoalSummary {
        let now = Date()
        let cap: Double = 112
        let segments: [WeeklyProjectGoalSummary.Segment] = [
            .init(id: UUID(), title: "Research", gradientIndex: 0, goalHours: 42, actualHours: 24),
            .init(id: UUID(), title: "Writing", gradientIndex: 1, goalHours: 32, actualHours: 18),
            .init(id: UUID(), title: "Planning", gradientIndex: 2, goalHours: 18, actualHours: 10),
            .init(id: UUID(), title: "Review", gradientIndex: 3, goalHours: 12, actualHours: 5)
        ]
        let raw = segments.reduce(0) { $0 + $1.goalHours }
        let scale = raw > cap ? cap / raw : 1
        return WeeklyProjectGoalSummary(
            weekStart: now,
            weekEnd: now.addingTimeInterval(7 * 24 * 3600),
            rawGoalHours: raw,
            totalGoalHours: raw * scale,
            scaleFactor: scale,
            segments: segments
        )
    }
}
