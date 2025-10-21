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
        ZStack(alignment: .topLeading) {
            ContainerRelativeShape()
                .fill(WeeklyGoalWidgetPalette.haloGradient)
                .opacity(0.35)
            Group {
                if let projection = entry.projection {
                    switch family {
                    case .systemSmall:
                        WeeklyGoalSmallView(projection: projection)
                    case .systemLarge:
                        WeeklyGoalLargeView(projection: projection)
                    default:
                        WeeklyGoalMediumView(projection: projection)
                    }
                } else {
                    WeeklyGoalPlaceholderView(family: family)
                }
            }
            .padding(paddingValue)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .containerBackground(for: .widget) { WeeklyGoalWidgetPalette.baseBackground }
    }

    private var paddingValue: CGFloat {
        switch family {
        case .systemSmall:
            return 30
        case .systemLarge:
            return 30
        default:
            return 30
        }
    }
}

// MARK: - Medium

private struct WeeklyGoalMediumView: View {
    let projection: WeeklyGoalProjection

    private var completionPercent: Int {
        guard projection.goalHours > 0 else { return 0 }
        return Int(round(projection.completionFraction * 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            WeeklyGoalProgressBar(value: projection.completionFraction)
                .frame(height: 10)
            metricsRow
            if let plan = todayPlan {
                todaySummary(plan: plan)
            }
            if !projection.primeHourLabels.isEmpty {
                primeSummary
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Focus Goal")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                Text(String(format: "%.1fh of %.0fh", projection.actualHours, projection.goalHours))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titleSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            Text("\(completionPercent)%")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
        }
        .padding(.top, 4)
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: 18) {
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

    private func todaySummary(plan: WeeklyGoalProjection.DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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

    private var primeSummary: some View {
        HStack(spacing: 6) {
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

    private var todayPlan: WeeklyGoalProjection.DayPlan? {
        projection.dayPlans.first { Calendar.current.isDateInToday($0.dayStart) }
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

    private var completionPercent: Int {
        guard projection.goalHours > 0 else { return 0 }
        return Int(round(projection.completionFraction * 100))
    }

    private var todayPlan: WeeklyGoalProjection.DayPlan? {
        projection.dayPlans.first { Calendar.current.isDateInToday($0.dayStart) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Focus Goal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                Spacer()
                Text("\(completionPercent)%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
            }

            Text(String(format: "%.1fh of %.0fh", projection.actualHours, projection.goalHours))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            WeeklyGoalProgressBar(value: projection.completionFraction)
                .frame(height: 8)

            if let plan = todayPlan {
                Text(String(format: "Today %.1fh / %.1fh", plan.actualHours, max(plan.plannedHours, 0.1)))
                    .font(.caption2)
                    .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if let label = projection.primeHourLabels.first {
                Label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } icon: {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WeeklyGoalWidgetPalette.accentHigh)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large

private struct WeeklyGoalLargeView: View {
    let projection: WeeklyGoalProjection

    private var completionPercent: Int {
        guard projection.goalHours > 0 else { return 0 }
        return Int(round(projection.completionFraction * 100))
    }

    private var planRows: [WeeklyGoalProjection.DayPlan] {
        Array(projection.dayPlans.prefix(7))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekly Focus Goal")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                    Text(String(format: "%.1fh of %.0fh (\(completionPercent)%%)", projection.actualHours, projection.goalHours))
                        .font(.headline.weight(.medium))
                        .foregroundStyle(WeeklyGoalWidgetPalette.titleSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.1fh remaining", projection.remainingHours))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                    Text(String(format: "≈%.1fh / day", projection.recommendedDailyHours))
                        .font(.caption2)
                        .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
                }
            }

            WeeklyGoalProgressBar(value: projection.completionFraction)

            HStack(spacing: 18) {
                MetricBlock(
                    title: "Today Logged",
                    value: String(format: "%.1fh", projection.todayActualHours),
                    footnote: projection.todayAdditionalHoursNeeded > 0
                        ? String(format: "+%.1fh more", projection.todayAdditionalHoursNeeded)
                        : "On pace",
                    accent: WeeklyGoalWidgetPalette.accentGradient
                )
                MetricBlock(
                    title: "Prime Hours",
                    value: projection.primeHourLabels.first ?? "—",
                    footnote: projection.primeHourLabels.dropFirst().joined(separator: ", "),
                    accent: WeeklyGoalWidgetPalette.accentGradient
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Week outlook")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)

                ForEach(planRows) { plan in
                    WeeklyGoalDayRow(plan: plan)
                }
            }

            Spacer(minLength: 0)

            Text("Hit your target early? Bank the surplus for later in the week—or level up next week’s goal.")
                .font(.caption2)
                .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WeeklyGoalDayRow: View {
    let plan: WeeklyGoalProjection.DayPlan

    private var weekdayLabel: String {
        WeekdayFormatter.shared.string(from: plan.dayStart)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekdayLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeklyGoalWidgetPalette.titlePrimary)
                Text(String(format: "%.1fh", plan.actualHours))
                    .font(.caption2)
                    .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let planned = max(plan.plannedHours, 0.01)
                let actual = max(plan.actualHours, 0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(WeeklyGoalWidgetPalette.progressTrack)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(WeeklyGoalWidgetPalette.accentGradient)
                        .frame(width: width * CGFloat(min(planned / max(planned, actual), 1)))
                        .opacity(0.35)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(WeeklyGoalWidgetPalette.accentGradient)
                        .frame(width: width * CGFloat(min(actual / max(planned, actual), 1)))
                }
            }
            .frame(height: 10)

            if plan.isFuture {
                Text(String(format: "%.1fh", plan.plannedHours))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WeeklyGoalWidgetPalette.bodyMuted)
            } else {
                Text("done")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WeeklyGoalWidgetPalette.accentGradient)
            }
        }
        .frame(height: 26)
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
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeeklyGoalProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(WeeklyGoalWidgetPalette.progressTrack)
                RoundedRectangle(cornerRadius: 5)
                    .fill(WeeklyGoalWidgetPalette.accentGradient)
                    .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 10)
    }
}

private struct WeeklyGoalPlaceholderView: View {
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
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

   static let haloGradient = LinearGradient(
       colors: [
           Color.white.opacity(0.2),
           Color.white.opacity(0.0)
       ],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )

    static let accentHigh = Color.white.opacity(0.95)
    static let titlePrimary = Color.white.opacity(0.92)
    static let titleSecondary = Color.white.opacity(0.78)
    static let bodyMuted = Color.white.opacity(0.65)
    static let progressTrack = Color.white.opacity(0.18)
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
