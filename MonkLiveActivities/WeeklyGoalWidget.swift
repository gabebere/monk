import WidgetKit
import SwiftUI
import SwiftData

struct WeeklyGoalWidgetEntry: TimelineEntry {
    let date: Date
    let projection: WeeklyGoalProjection?
}

struct WeeklyGoalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyGoalWidgetEntry {
        WeeklyGoalWidgetEntry(date: .now, projection: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalWidgetEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(WeeklyGoalWidgetEntry(date: now, projection: .preview))
        } else {
            completion(WeeklyGoalWidgetEntry(date: now, projection: WeeklyGoalWidgetDataSource.loadProjection(now: now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalWidgetEntry>) -> Void) {
        let now = Date()
        let projection = WeeklyGoalWidgetDataSource.loadProjection(now: now)
        let entry = WeeklyGoalWidgetEntry(date: now, projection: projection)
        let refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeeklyGoalWidget", provider: WeeklyGoalWidgetProvider()) { entry in
            WeeklyGoalWidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .configurationDisplayName("Weekly Focus Plan")
        .description("Glance at your goal pace, daily plan, and prime focus windows.")
    }
}

private struct WeeklyGoalWidgetView: View {
    let entry: WeeklyGoalWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let metrics = WeeklyGoalWidgetLayout.metrics(for: family)

        ZStack(alignment: .topLeading) {
            Group {
                if let projection = entry.projection {
                    switch family {
                    case .systemSmall:
                        WeeklyGoalSmallView(projection: projection, layout: metrics)
                    case .systemLarge:
                        WeeklyGoalLargeView(projection: projection, layout: metrics)
                    default:
                        WeeklyGoalMediumView(projection: projection, layout: metrics)
                    }
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
    let metricSpacing: CGFloat
    let progressHeight: CGFloat

    static func metrics(for family: WidgetFamily) -> WeeklyGoalWidgetLayout {
        switch family {
        case .systemSmall:
            return WeeklyGoalWidgetLayout(
                outerPadding: 8,
                verticalPadding: 8,
                sectionSpacing: 10,
                headerSpacing: 6,
                metricSpacing: 12,
                progressHeight: 8
            )
        case .systemMedium:
            return WeeklyGoalWidgetLayout(
                outerPadding: 16,
                verticalPadding: 8,
                sectionSpacing: 12,
                headerSpacing: 6,
                metricSpacing: 14,
                progressHeight: 9
            )
        case .systemLarge:
            return WeeklyGoalWidgetLayout(
                outerPadding: 18,
                verticalPadding: 12,
                sectionSpacing: 16,
                headerSpacing: 8,
                metricSpacing: 18,
                progressHeight: 12
            )
        default:
            return WeeklyGoalWidgetLayout(
                outerPadding: 18,
                verticalPadding: 12,
                sectionSpacing: 14,
                headerSpacing: 6,
                metricSpacing: 16,
                progressHeight: 10
            )
        }
    }
}

// MARK: - Medium

private struct WeeklyGoalMediumView: View {
    let projection: WeeklyGoalProjection
    let layout: WeeklyGoalWidgetLayout

    private var completionPercent: Int {
        guard projection.goalHours > 0 else { return 0 }
        return Int(round(projection.completionFraction * 100))
    }

    private var todayPlan: WeeklyGoalProjection.DayPlan? {
        projection.dayPlans.first { Calendar.current.isDateInToday($0.dayStart) }
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let scale = min(1.0, max(0.85, height / 158.0))
            let sectionSpacing = max(8, layout.sectionSpacing * scale)
            let headerSpacing = max(4, layout.headerSpacing * scale)
            let metricSpacing = max(10, layout.metricSpacing * scale)
            let progressHeight = max(6, layout.progressHeight * scale)
            let percentSize = max(20, 24 * scale)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    header(headerSpacing: headerSpacing, percentSize: percentSize)
                    WeeklyGoalProgressBar(value: projection.completionFraction, height: progressHeight)
                        .frame(maxWidth: .infinity)
                    metricsRow(metricSpacing: metricSpacing)
                    if let plan = todayPlan {
                        todaySummary(plan: plan, headerSpacing: headerSpacing)
                    }
                    if !projection.primeHourLabels.isEmpty {
                        primeSummary(headerSpacing: headerSpacing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, layout.sectionSpacing / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(headerSpacing: CGFloat, percentSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: headerSpacing) {
                Text("Weekly Focus Goal")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(String(format: "%.1fh of %.0fh", projection.actualHours, projection.goalHours))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titleSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            Text("\(completionPercent)%")
                .font(.system(size: percentSize, weight: .heavy, design: .rounded))
                .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func metricsRow(metricSpacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: metricSpacing) {
            MetricBlock(
                title: "Remaining",
                value: String(format: "%.1fh", projection.remainingHours),
                footnote: projection.remainingDays > 0
                    ? "\(projection.remainingDays) day\(projection.remainingDays == 1 ? "" : "s") left"
                    : "Goal complete",
                accent: WeeklyGoalWidgetPalette.accentGradient
            )

            MetricBlock(
                title: "Daily Pace",
                value: String(format: "%.1fh", projection.recommendedDailyHours),
                footnote: paceFootnote,
                accent: WeeklyGoalWidgetPalette.accentGradient
            )
        }
    }

    private func todaySummary(plan: WeeklyGoalProjection.DayPlan, headerSpacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
            Text(String(format: "%.1fh logged • %.1fh target", plan.actualHours, max(plan.plannedHours, 0.1)))
                .font(.caption2)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func primeSummary(headerSpacing: CGFloat) -> some View {
        HStack(spacing: headerSpacing) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
            Text("Best hours: \(projection.primeHourLabels.joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var paceFootnote: String {
        if projection.todayAdditionalHoursNeeded <= 0 {
            return String(format: "%.1fh logged", projection.todayActualHours)
        }
        return String(format: "+%.1fh today", projection.todayAdditionalHoursNeeded)
    }
}

// MARK: - Small

private struct WeeklyGoalSmallView: View {
    let projection: WeeklyGoalProjection
    let layout: WeeklyGoalWidgetLayout

    private var completionPercent: Int {
        guard projection.goalHours > 0 else { return 0 }
        return Int(round(projection.completionFraction * 100))
    }

    private var todayPlan: WeeklyGoalProjection.DayPlan? {
        projection.dayPlans.first { Calendar.current.isDateInToday($0.dayStart) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            Text("Focus Goal")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(String(format: "%.1fh of %.0fh", projection.actualHours, projection.goalHours))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            WeeklyGoalProgressBar(value: projection.completionFraction, height: layout.progressHeight)
                .frame(maxWidth: .infinity)

            if let plan = todayPlan {
                Text(String(format: "Today %.1fh / %.1fh", plan.actualHours, max(plan.plannedHours, 0.1)))
                    .font(.caption2)
                    .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let label = projection.primeHourLabels.first {
                HStack(spacing: layout.headerSpacing) {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("\(completionPercent)%")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, max(0, (layout.outerPadding / 2) - 2))
    }
}

// MARK: - Large

private struct WeeklyGoalLargeView: View {
    let projection: WeeklyGoalProjection
    let layout: WeeklyGoalWidgetLayout

    private var completionPercent: Int {
        guard projection.goalHours > 0 else { return 0 }
        return Int(round(projection.completionFraction * 100))
    }

    private var planRows: [WeeklyGoalProjection.DayPlan] {
        Array(projection.dayPlans.prefix(7))
    }

    private var remainingFootnote: String {
        projection.remainingDays > 0
            ? "\(projection.remainingDays) day\(projection.remainingDays == 1 ? "" : "s") left"
            : "Goal complete"
    }

    private var todayMetricFootnote: String {
        let delta = projection.todayActualHours - projection.todayRecommendedHours
        if delta > 0.2 {
            return String(format: "+%.1fh ahead", delta)
        } else if delta < -0.2 {
            return String(format: "%.1fh to go", abs(delta))
        } else {
            return "On pace"
        }
    }

    private var paceFootnote: String {
        if projection.remainingDays > 0 {
            return String(format: "Next avg %.1fh", projection.recommendedDailyHours)
        } else {
            return "Plan next goal"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let scale = min(1.0, max(0.82, min(width / 338.0, height / 354.0)))
            let sectionSpacing = max(12, layout.sectionSpacing * scale)
            let headerSpacing = max(6, layout.headerSpacing * scale)
            let metricSpacing = max(12, layout.metricSpacing * scale)
            let progressHeight = max(10, layout.progressHeight * scale)

            VStack(alignment: .leading, spacing: sectionSpacing) {
                progressSection(
                    scale: scale,
                    headerSpacing: headerSpacing,
                    progressHeight: max(progressHeight, 12)
                )

                metricsRow(metricSpacing: metricSpacing)

                if !projection.primeHourLabels.isEmpty {
                    primeWindowsRow(headerSpacing: headerSpacing)
                }

                weekPlanSection(headerSpacing: headerSpacing, barHeight: max(progressHeight * 4.5, 48))
            }
            .padding(.vertical, layout.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func progressSection(scale: CGFloat, headerSpacing: CGFloat, progressHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly Progress")
                    .font(.system(size: 22 * scale, weight: .semibold))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Text("\(completionPercent)%")
                    .font(.system(size: 26 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            WeeklyGoalProgressBar(value: projection.completionFraction, height: progressHeight)
                .frame(maxWidth: .infinity)

            Text(String(format: "%.1fh logged this week", projection.actualHours))
                .font(.footnote.weight(.medium))
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricsRow(metricSpacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: metricSpacing) {
            MetricBlock(
                title: "Remaining",
                value: String(format: "%.1fh", projection.remainingHours),
                footnote: remainingFootnote,
                accent: WeeklyGoalWidgetPalette.accentGradient
            )

            MetricBlock(
                title: "Today",
                value: String(format: "%.1fh", projection.todayActualHours),
                footnote: todayMetricFootnote,
                accent: WeeklyGoalWidgetPalette.accentGradient
            )

            MetricBlock(
                title: "Daily Pace",
                value: String(format: "%.1fh", projection.recommendedDailyHours),
                footnote: paceFootnote,
                accent: WeeklyGoalWidgetPalette.accentGradient
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func primeWindowsRow(headerSpacing: CGFloat) -> some View {
        VStack(alignment: .center, spacing: headerSpacing) {
            Text("Prime focus windows")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                .textCase(.uppercase)
                .kerning(0.8)

            HStack(spacing: headerSpacing) {
                ForEach(projection.primeHourLabels.prefix(3), id: \.self) { label in
                    WeeklyGoalChip(label: label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func weekPlanSection(headerSpacing: CGFloat, barHeight: CGFloat) -> some View {
        WeeklyGoalWeekStrip(
            plans: planRows,
            barHeight: barHeight,
            headerSpacing: headerSpacing
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct WeeklyGoalWeekStrip: View {
    let plans: [WeeklyGoalProjection.DayPlan]
    let barHeight: CGFloat
    let headerSpacing: CGFloat

    private var maximumHours: Double {
        max(plans.map { max($0.actualHours, $0.plannedHours) }.max() ?? 1, 0.5)
    }

    var body: some View {
        VStack(alignment: .center, spacing: headerSpacing) {
            Text("Week plan")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(plans) { plan in
                    WeeklyGoalDayColumn(
                        plan: plan,
                        maxHours: maximumHours,
                        barHeight: barHeight,
                        isToday: Calendar.current.isDateInToday(plan.dayStart)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct WeeklyGoalDayColumn: View {
    let plan: WeeklyGoalProjection.DayPlan
    let maxHours: Double
    let barHeight: CGFloat
    let isToday: Bool

    private var barWidth: CGFloat { 28 }
    private var cornerRadius: CGFloat { barWidth / 2 }

    private var weekdayLabel: String {
        WeekdayFormatter.shared.string(from: plan.dayStart)
    }

    private var footerLabel: String {
        if plan.isFuture {
            return String(format: "%.1fh", max(plan.plannedHours, 0))
        }
        return String(format: "%.1fh", plan.actualHours)
    }

    @ViewBuilder
    private func fillShape(height: CGFloat, style: some ShapeStyle, roundTop: Bool, roundBottom: Bool) -> some View {
        if height > 0 {
            let cappedBottomRadius = roundBottom ? min(cornerRadius, height / 2) : 0
            let topRadius = roundTop ? min(cornerRadius, height / 2) : 0
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: topRadius,
                    bottomLeading: cappedBottomRadius,
                    bottomTrailing: cappedBottomRadius,
                    topTrailing: topRadius
                )
            )
            .fill(style)
            .frame(width: barWidth, height: height)
        }
    }

    var body: some View {
        let plannedRatio = min(max(plan.plannedHours / maxHours, 0), 1)
        let actualRatio = min(max(plan.actualHours / maxHours, 0), 1)
        let minSegmentHeight: CGFloat = cornerRadius * 2
        let plannedHeight = plannedRatio > 0 ? min(barHeight, max(barHeight * plannedRatio, minSegmentHeight)) : 0
        let actualHeight = plan.actualHours > 0
        ? min(barHeight, max(barHeight * actualRatio, minSegmentHeight))
        : 0
        let remainderHeight = max(plannedHeight - actualHeight, 0)
        let dayComplete = plan.actualHours >= max(plan.plannedHours, 0.01) - 0.05
        let actualRoundsTop = dayComplete && actualHeight > 0

        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(WeeklyGoalWidgetPalette.progressTrack)
                    .frame(width: barWidth, height: barHeight)

                if remainderHeight > 0 && plan.isFuture {
                    fillShape(
                        height: remainderHeight,
                        style: WeeklyGoalWidgetPalette.accentGradient.opacity(0.35),
                        roundTop: true,
                        roundBottom: actualHeight == 0
                    )
                    .offset(y: -actualHeight)
                }

                if actualHeight > 0 {
                    fillShape(
                        height: actualHeight,
                        style: WeeklyGoalWidgetPalette.accentGradient,
                        roundTop: actualRoundsTop,
                        roundBottom: true
                    )
                }
            }
            .frame(width: barWidth, height: barHeight, alignment: .bottom)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isToday ? WeeklyGoalWidgetPalette.accentHigh.opacity(0.45) : Color.clear,
                        lineWidth: isToday ? 2 : 0
                    )
            )

            Text(isToday ? "TODAY" : weekdayLabel.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(footerLabel)
                .font(.caption2)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: barWidth)
    }
}

private struct WeeklyGoalChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(WeeklyGoalWidgetPalette.chipBackground)
            )
            .overlay(
                Capsule()
                    .stroke(WeeklyGoalWidgetPalette.chipStroke, lineWidth: 1)
            )
    }
}

// MARK: - Shared Components

private struct MetricBlock: View {
    let title: String
    let value: String
    let footnote: String
    var accent: LinearGradient? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
            if let accent {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(accent)
            } else {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
            }
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeeklyGoalProgressBar: View {
    let value: Double
    let height: CGFloat

    init(value: Double, height: CGFloat = 10) {
        self.value = value
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(WeeklyGoalWidgetPalette.progressTrack)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(WeeklyGoalWidgetPalette.accentGradient)
                    .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

private struct WeeklyGoalPlaceholderView: View {
    let family: WidgetFamily
    let layout: WeeklyGoalWidgetLayout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            Text("Weekly Focus Goal")
                .font(family == .systemSmall ? .headline.weight(.semibold) : .title2.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
            Text("Set a weekly goal in Monk to see your plan here.")
                .font(family == .systemSmall ? .caption : .subheadline)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Palette & Helpers

private enum WeeklyGoalWidgetPalette {
    static let baseBackground = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.07, blue: 0.26),
            Color(red: 0.19, green: 0.12, blue: 0.37),
            Color(red: 0.10, green: 0.29, blue: 0.47),
            Color(red: 0.05, green: 0.48, blue: 0.56)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.47, green: 0.43, blue: 0.96),
            Color(red: 0.24, green: 0.57, blue: 0.98),
            Color(red: 0.12, green: 0.73, blue: 0.84)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let accentHigh = Color.white.opacity(0.95)
    static let titlePrimary = Color.white.opacity(0.92)
    static let titleSecondary = Color.white.opacity(0.78)
    static let bodyMuted = Color.white.opacity(0.65)
    static let progressTrack = Color.white.opacity(0.18)
    static let chipBackground = Color.white.opacity(0.12)
    static let chipStroke = Color.white.opacity(0.22)
}

private enum WeeklyGoalWidgetDataSource {
    static func loadProjection(now: Date) -> WeeklyGoalProjection? {
        do {
            let schema = Schema([FocusSession.self, Preferences.self, Project.self])
            let configuration = ModelConfiguration(cloudKitDatabase: .private("iCloud.com.gbr.Monk"))
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)

            let prefs = try context.fetch(FetchDescriptor<Preferences>()).first
            let weeklyGoal = prefs?.weeklyGoalHours ?? 0
            guard weeklyGoal > 0 else { return nil }

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
            return analyzer.weeklyGoalProjection(sessions: sessions, weeklyGoalHours: weeklyGoal, now: now)
        } catch {
            return nil
        }
    }
}

private extension WeeklyGoalProjection {
    static let placeholder: WeeklyGoalProjection = .mock(goalHours: 35, actualHours: 18, remainingHours: 17, remainingDays: 4, todayActual: 2.2, todayRecommended: 2.6, todayAdditional: 0.4)
    static let preview: WeeklyGoalProjection = .mock(goalHours: 45, actualHours: 32, remainingHours: 13, remainingDays: 3, todayActual: 4.2, todayRecommended: 3.6, todayAdditional: -0.6)

    static func mock(goalHours: Double,
                     actualHours: Double,
                     remainingHours: Double,
                     remainingDays: Int,
                     todayActual: Double,
                     todayRecommended: Double,
                     todayAdditional: Double) -> WeeklyGoalProjection {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let plans: [WeeklyGoalProjection.DayPlan] = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 3, to: today) else { return nil }
            let isFuture = day > today
            let planned = max(todayRecommended, 2.0) + Double(offset - 3) * 0.3
            let actual = isFuture ? max(0, Double.random(in: 0.0...planned * 0.6)) : max(0, planned * Double.random(in: 0.7...1.1))
            return WeeklyGoalProjection.DayPlan(
                dayStart: day,
                actualHours: offset == 3 ? todayActual : actual,
                plannedHours: offset == 3 ? todayRecommended : planned,
                isFuture: isFuture
            )
        }
        return WeeklyGoalProjection(
            goalHours: goalHours,
            actualHours: actualHours,
            completionFraction: goalHours > 0 ? min(1, actualHours / goalHours) : 0,
            remainingHours: max(0, remainingHours),
            remainingDays: remainingDays,
            recommendedDailyHours: remainingDays > 0 ? remainingHours / Double(remainingDays) : 0,
            todayActualHours: todayActual,
            todayRecommendedHours: todayRecommended,
            todayAdditionalHoursNeeded: max(0, todayAdditional),
            primeHourLabels: ["10–11", "14–15", "20–21"],
            dayPlans: plans
        )
    }
}

private final class WeekdayFormatter {
    static let shared = WeekdayFormatter()
    private let formatter: DateFormatter

    private init() {
        formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
    }

    func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
