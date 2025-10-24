import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt, order: .reverse)]) private var sessions: [FocusSession]
    @Query private var prefsList: [Preferences]
    @State private var path: [InsightRoute] = []

    private let analyzer = InsightsAnalyzer()
    private let referenceNow = Date()

    private var prefs: Preferences? { prefsList.first }
    private var weeklyGoalHours: Double? { prefs?.weeklyGoalHours }

    private var summary: TemporalInsightsSummary {
        analyzer.summarize(sessions: sessions, now: referenceNow)
    }

    private var focusScoreSnapshot: FocusScoreSnapshot {
        analyzer.focusScore(
            sessions: sessions,
            weeklyGoalHours: weeklyGoalHours,
            now: referenceNow
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AnimatingBackground(base: Theme.dataBackground(), halo: Theme.dataHaloGradient)
                ScrollView {
                    LazyVStack(spacing: InsightsLayout.verticalSpacing) {
                        NavigationLink(value: InsightRoute.focusScore) {
                            FocusScoreCard(model: focusScoreSnapshot, palette: InsightPalette.focusScore)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(InsightsLayout.focusScoreAspectRatio, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, InsightsLayout.focusScoreGap)
                        .simultaneousGesture(TapGesture().onEnded { Haptics.soft() })

                        LazyVGrid(columns: gridColumns, spacing: InsightsLayout.verticalSpacing) {
                            if let goalHours = weeklyGoalHours, goalHours > 0 {
                                NavigationLink(value: InsightRoute.weeklyGoal) {
                                    InsightTile(model: weeklyGoalTile(summary: summary, goalHours: goalHours))
                                }
                                .simultaneousGesture(TapGesture().onEnded { Haptics.soft() })
                            }

                            ForEach(tileModels(summary: summary)) { tile in
                                NavigationLink(value: tile.route) {
                                    InsightTile(model: tile)
                                }
                                .simultaneousGesture(TapGesture().onEnded { Haptics.soft() })
                            }
                        }
                    }
                    .padding(.horizontal, InsightsLayout.horizontalPadding)
                    .padding(.top, InsightsLayout.topPadding)
                    .padding(.bottom, InsightsLayout.bottomPadding)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: InsightsLayout.bottomInset)
                }
            }
            .navigationTitle("Insights")
            .navigationDestination(for: InsightRoute.self) { route in
                switch route {
                case .focusScore:
                    FocusScoreDetailView(
                        analyzer: analyzer,
                        sessions: sessions,
                        weeklyGoalHours: weeklyGoalHours,
                        palette: InsightPalette.focusScore,
                        now: referenceNow
                    )
                case .weeklyGoal:
                    WeeklyGoalDetailView(
                        sessions: sessions,
                        analyzer: analyzer,
                        weeklyGoalHours: weeklyGoalHours ?? 0,
                        palette: InsightPalette.goal,
                        now: referenceNow
                    )
                case .focus:
                    InsightDetailView(kind: .focusTotals, palette: InsightPalette.focus, sessions: sessions, analyzer: analyzer, now: referenceNow)
                case .satisfaction:
                    InsightDetailView(kind: .satisfaction, palette: InsightPalette.satisfaction, sessions: sessions, analyzer: analyzer, now: referenceNow)
                case .consistency:
                    InsightDetailView(kind: .consistency, palette: InsightPalette.consistency, sessions: sessions, analyzer: analyzer, now: referenceNow)
                case .primeHours:
                    InsightDetailView(kind: .primeHours, palette: InsightPalette.prime, sessions: sessions, analyzer: analyzer, now: referenceNow)
                case .rhythm:
                    InsightDetailView(kind: .rhythm, palette: InsightPalette.rhythm, sessions: sessions, analyzer: analyzer, now: referenceNow)
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: InsightsLayout.verticalSpacing),
         GridItem(.flexible(), spacing: InsightsLayout.verticalSpacing)]
    }

    private func weeklyGoalTile(summary: TemporalInsightsSummary, goalHours: Double) -> InsightTileModel {
        let totalHours = summary.totalFocusSeconds / 3600
        let completion = goalHours > 0 ? min(max(totalHours / goalHours, 0), 1) : 0
        let headline = String(format: "%.0f%%", completion * 100)
        let subline = String(format: "%.1fh of %.0fh", totalHours, goalHours)
        return InsightTileModel(
            route: .weeklyGoal,
            title: "Weekly Goal",
            icon: "flag.checkered",
            colors: InsightPalette.goal,
            headline: headline,
            footnote: subline
        )
    }

    private func tileModels(summary: TemporalInsightsSummary) -> [InsightTileModel] {
        InsightKind.allCases.map { kind in
            switch kind {
            case .focusTotals:
                let totalHours = summary.totalFocusSeconds / 3600
                let sessionsCount = summary.sampleSessionCount
                return InsightTileModel(
                    route: kind.route,
                    title: kind.title,
                    icon: kind.icon,
                    colors: InsightPalette.focus,
                    headline: String(format: "%.1fh", totalHours),
                    footnote: "\(sessionsCount) sessions"
                )
            case .satisfaction:
                let average = summary.averageSatisfaction.map { String(format: "%.1f/10", $0) } ?? "—"
                let notedDays = summary.dailySnapshots.filter { $0.averageSatisfaction != nil }.count
                let footnote = notedDays > 0 ? "Mood logged on \(notedDays) days" : "Log moods to unlock trends"
                return InsightTileModel(
                    route: kind.route,
                    title: kind.title,
                    icon: kind.icon,
                    colors: InsightPalette.satisfaction,
                    headline: average,
                    footnote: footnote
                )
            case .consistency:
                let headline = "\(summary.dailyStreakCount)d streak"
                let footnote = "\(summary.activeDayCount)/\(summary.lookbackDays) days active"
                return InsightTileModel(
                    route: kind.route,
                    title: kind.title,
                    icon: kind.icon,
                    colors: InsightPalette.consistency,
                    headline: headline,
                    footnote: footnote
                )
            case .primeHours:
                let headline = summary.bestWindow.map { window in
                    "\(hourLabel(window.startHour)) – \(hourLabel(window.endHour))"
                } ?? "Need more data"
                let footnote = summary.bestWindow?.averageSatisfaction.map { String(format: "Avg %.1f/10", $0) } ?? "Run sessions at new times"
                return InsightTileModel(
                    route: kind.route,
                    title: kind.title,
                    icon: kind.icon,
                    colors: InsightPalette.prime,
                    headline: headline,
                    footnote: footnote
                )
            case .rhythm:
                let headline = summary.topHourMetrics.first.map { hourLabel($0.hour) } ?? "No data"
                let footnote = summary.topHourMetrics.first.map { String(format: "%.0f min logged", $0.totalSeconds / 60) } ?? "Log more focus time"
                return InsightTileModel(
                    route: kind.route,
                    title: kind.title,
                    icon: kind.icon,
                    colors: InsightPalette.rhythm,
                    headline: headline,
                    footnote: footnote
                )
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("j")
        let reference = Calendar(identifier: .gregorian).date(from: comps) ?? Date()
        return formatter.string(from: reference)
    }
}

private enum InsightRoute: Hashable {
    case focusScore
    case weeklyGoal
    case focus
    case satisfaction
    case consistency
    case primeHours
    case rhythm
}

private enum InsightKind: CaseIterable {
    case focusTotals
    case satisfaction
    case consistency
    case primeHours
    case rhythm

    var route: InsightRoute {
        switch self {
        case .focusTotals: return .focus
        case .satisfaction: return .satisfaction
        case .consistency: return .consistency
        case .primeHours: return .primeHours
        case .rhythm: return .rhythm
        }
    }

    var title: String {
        switch self {
        case .focusTotals: return "Focus Totals"
        case .satisfaction: return "Satisfaction"
        case .consistency: return "Consistency"
        case .primeHours: return "Prime Hours"
        case .rhythm: return "Daily Rhythm"
        }
    }

    var icon: String {
        switch self {
        case .focusTotals: return "hourglass"
        case .satisfaction: return "face.smiling"
        case .consistency: return "flame"
        case .primeHours: return "clock.badge.checkmark"
        case .rhythm: return "waveform.path.ecg"
        }
    }
}

private enum InsightsLayout {
    static let horizontalPadding: CGFloat = 20
    static let verticalSpacing: CGFloat = 16
    static let topPadding: CGFloat = 32
    static let bottomPadding: CGFloat = 48
    static let bottomInset: CGFloat = 72
    static let focusScoreAspectRatio: CGFloat = 2.0
    static let focusScoreGap: CGFloat = verticalSpacing
}

private struct FocusScoreCard: View {
    let model: FocusScoreSnapshot
    let palette: InsightPalette.Colors

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let ringSize = min(height * 0.44, width * 0.26)
            let sectionSpacing: CGFloat = 8

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(InsightPalette.gradient(for: palette))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: palette.primary.opacity(0.18), radius: 16, x: 0, y: 10)

                VStack(alignment: .leading, spacing: sectionSpacing) {
                    Label {
                        Text("Focus Score")
                            .font(.headline)
                            .foregroundStyle(Color.white.opacity(0.95))
                    } icon: {
                        Image(systemName: "scope")
                            .foregroundStyle(Color.white.opacity(0.9))
                    }

                    HStack(alignment: .center, spacing: 12) {
                        FocusScoreRing(model: model, diameter: ringSize)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.rating.rawValue)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .minimumScaleFactor(0.85)
                            if let delta = model.delta, model.hasData {
                                FocusScoreDeltaBadge(delta: delta)
                            } else {
                                Text("Trailing \(model.timeline.count) days")
                                    .font(.caption2)
                                    .foregroundStyle(Color.white.opacity(0.75))
                            }
                            Text(summaryLine)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.15))

                    if !model.components.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(model.components) { component in
                                FocusScoreComponentColumn(component: component)
                            }
                        }
                    } else {
                        Text("Log focus sessions to unlock your personalized score.")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, max(18, width * 0.06))
            }
        }
    }

    private var summaryLine: String {
        guard let today = model.today else {
            return "Focus metrics appear once you log sessions."
        }

        if model.dailyTargetHours > 0 {
            return String(format: "%.1fh today • %.1fh target", today.actualHours, model.dailyTargetHours)
        }

        return String(format: "%.1fh focused today", today.actualHours)
    }
}

private struct FocusScoreRing: View {
    let model: FocusScoreSnapshot
    let diameter: CGFloat
    private let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(segment.color)
                    .rotationEffect(.degrees(-90))
            }
            Text("\(model.score)")
                .font(.system(size: diameter * 0.36, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    private struct Segment: Identifiable {
        let kind: FocusScoreSnapshot.Component.Kind
        let start: Double
        let end: Double

        var id: FocusScoreSnapshot.Component.Kind { kind }
        var color: Color { FocusScoreStyling.color(for: kind) }
    }

    private var segments: [Segment] {
        var items: [Segment] = []
        var cursor: Double = 0
        for component in model.components {
            let length = max(0, min(component.points / 100, 1))
            guard length > 0 else { continue }
            let start = cursor
            let end = min(cursor + length, 1)
            items.append(Segment(kind: component.kind, start: start, end: end))
            cursor = end
        }
        return items
    }
}

private struct FocusScoreDeltaBadge: View {
    let delta: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
            Text(labelText)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
    }

    private var symbolName: String {
        if delta > 0 { return "arrow.up" }
        if delta < 0 { return "arrow.down" }
        return "equal"
    }

    private var labelText: String {
        if delta > 0 { return "Up \(delta) vs yesterday" }
        if delta < 0 { return "Down \(abs(delta)) vs yesterday" }
        return "Even with yesterday"
    }

    private var backgroundColor: Color {
        if delta > 0 { return FocusScoreStyling.positiveBackground }
        if delta < 0 { return FocusScoreStyling.negativeBackground }
        return Color.white.opacity(0.18)
    }

    private var foregroundColor: Color {
        if delta > 0 { return FocusScoreStyling.positiveForeground }
        if delta < 0 { return FocusScoreStyling.negativeForeground }
        return Color.white.opacity(0.9)
    }
}

private struct FocusScoreComponentColumn: View {
    let component: FocusScoreSnapshot.Component

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(FocusScoreStyling.color(for: component.kind).opacity(component.hasData ? 1 : 0.35))
                    .frame(width: 7, height: 7)
                Text(component.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(component.hasData ? 0.9 : 0.65))
            }

            Text(detailText)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.72))
                 .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(pointsLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pointsLabel: String {
        let earned = Int(round(component.points))
        let maxPoints = Int(round(component.maxPoints))
        return "\(earned)/\(maxPoints)"
    }

    private var detailText: String {
        switch component.kind {
        case .goalPace:
            let target = component.targetValue ?? 0
            guard target > 0 else {
                return String(format: "%.1fh today", component.actualValue)
            }
            return String(format: "%.1fh of %.1fh target", component.actualValue, target)
        case .primeAlignment:
            guard component.hasData else {
                return "Need more data for prime hours"
            }
            let target = component.targetValue ?? 0
            guard target > 0 else {
                return String(format: "%.1fh in prime", component.actualValue)
            }
            return String(format: "%.1fh of %.1fh prime", component.actualValue, target)
        }
    }
}

private enum FocusScoreStyling {
    static func color(for kind: FocusScoreSnapshot.Component.Kind) -> Color {
        switch kind {
        case .goalPace:
            return Color(red: 0.33, green: 0.64, blue: 0.99)
        case .primeAlignment:
            return Color(red: 0.39, green: 0.82, blue: 0.67)
        }
    }

    static let positiveBackground = Color(red: 0.36, green: 0.82, blue: 0.58).opacity(0.22)
    static let positiveForeground = Color.white
    static let negativeBackground = Color(red: 0.94, green: 0.45, blue: 0.37).opacity(0.22)
    static let negativeForeground = Color.white
}

private struct InsightTileModel: Identifiable {
    let id = UUID()
    let route: InsightRoute
    let title: String
    let icon: String
    let colors: InsightPalette.Colors
    let headline: String
    let footnote: String
}

private struct InsightTile: View {
    let model: InsightTileModel

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [model.colors.primary, model.colors.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: model.colors.primary.opacity(0.32), radius: 18, x: 0, y: 12)

                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text(model.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.95))
                    } icon: {
                        Image(systemName: model.icon)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Text(model.headline)
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.85)
                    Text(model.footnote)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .frame(width: side, height: side, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private enum InsightPalette {
    typealias Colors = (primary: Color, secondary: Color)

    static let focusScore: Colors = (
        Color(red: 0.27, green: 0.56, blue: 0.99),
        Color(red: 0.60, green: 0.28, blue: 0.98)
    )
    static let goal: Colors = (
        Color(red: 0.33, green: 0.76, blue: 0.86),
        Color(red: 0.20, green: 0.48, blue: 0.97)
    )
    static let focus: Colors = (
        Color(red: 0.34, green: 0.64, blue: 0.99),
        Color(red: 0.22, green: 0.30, blue: 0.64)
    )
    static let satisfaction: Colors = (
        Color(red: 0.99, green: 0.62, blue: 0.45),
        Color(red: 0.95, green: 0.30, blue: 0.55)
    )
    static let consistency: Colors = (
        Color(red: 0.54, green: 0.43, blue: 0.99),
        Color(red: 0.28, green: 0.21, blue: 0.58)
    )
    static let prime: Colors = (
        Color(red: 0.99, green: 0.45, blue: 0.69),
        Color(red: 0.58, green: 0.32, blue: 0.93)
    )
    static let rhythm: Colors = (
        Color(red: 0.98, green: 0.80, blue: 0.36),
        Color(red: 0.96, green: 0.48, blue: 0.31)
    )

    static func gradient(for colors: Colors) -> LinearGradient {
        LinearGradient(colors: [colors.primary, colors.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Detail surfaces, selectors, and shared views

private struct WeeklyGoalDetailView: View {
    let sessions: [FocusSession]
    let analyzer: InsightsAnalyzer
    let weeklyGoalHours: Double
    let palette: InsightPalette.Colors
    private let weekOffsets: [Int]
    private let baseNow: Date
    @State private var selectedWeek: Int

    init(sessions: [FocusSession], analyzer: InsightsAnalyzer, weeklyGoalHours: Double, palette: InsightPalette.Colors, now: Date = .now) {
        self.sessions = sessions
        self.analyzer = analyzer
        self.weeklyGoalHours = weeklyGoalHours
        self.palette = palette
        self.baseNow = now
        self.weekOffsets = analyzer.availableWeekOffsets(sessions: sessions, now: now)
        _selectedWeek = State(initialValue: 0)
    }

    private var summary: TemporalInsightsSummary {
        analyzer.summary(forWeekOffset: selectedWeek, sessions: sessions, now: baseNow)
    }

    var body: some View {
        let gradient = InsightPalette.gradient(for: palette)
        let dailySnapshots = summary.dailySnapshots
        let dailyTarget = weeklyGoalHours / Double(summary.lookbackDays)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WeekSelector(selectedWeek: $selectedWeek, weekOffsets: weekOffsets, summary: summary)

                MetricCapsules(metrics: [
                    Metric(title: "Total", value: String(format: "%.1fh", summary.totalFocusSeconds / 3600)),
                    Metric(title: "Goal", value: String(format: "%.0fh", weeklyGoalHours)),
                    Metric(title: "Progress", value: String(format: "%.0f%%", progress * 100))
                ])

                ProgressView(value: min(progress, 1))
                    .progressViewStyle(.linear)
                    .tint(.white)

                Text(String(format: "You are %@ schedule.", pacingText))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))

                Chart {
                    ForEach(dailySnapshots) { snapshot in
                        BarMark(
                            x: .value("Day", snapshot.dayStart),
                            y: .value("Focus", snapshot.totalSeconds / 3600)
                        )
                        .foregroundStyle(Color.white.opacity(0.75))
                    }
                    if dailyTarget > 0 {
                        RuleMark(y: .value("Target", dailyTarget))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel(String(format: "%.0fh", value.as(Double.self) ?? 0))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: dailySnapshots.map(\.dayStart)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.weekday(.abbreviated))
                            }
                            .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                }
                .frame(height: 200)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily breakdown")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.9))
                    ForEach(dailySnapshots) { snapshot in
                        GoalDayRow(
                            label: weekdayLabel(snapshot.dayStart),
                            actualHours: snapshot.totalSeconds / 3600,
                            targetHours: dailyTarget
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(gradient.ignoresSafeArea())
        .navigationTitle("Weekly Goal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progress: Double {
        guard weeklyGoalHours > 0 else { return 0 }
        return (summary.totalFocusSeconds / 3600) / weeklyGoalHours
    }

    private var pacingText: String {
        let elapsed = summary.weekEnd.timeIntervalSince(summary.weekStart)
        guard elapsed > 0 else { return "on" }
        let fraction = min(1, max(0, baseNow.timeIntervalSince(summary.weekStart) / elapsed))
        let expected = weeklyGoalHours * fraction
        let delta = (summary.totalFocusSeconds / 3600) - expected
        if abs(delta) < 0.25 { return "on" }
        return delta > 0 ? String(format: "%.1fh ahead of", delta) : String(format: "%.1fh behind", abs(delta))
    }

    private func weekdayLabel(_ date: Date) -> String {
        WeeklyGoalDetailView.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
}

private struct FocusScoreDetailView: View {
    let analyzer: InsightsAnalyzer
    let sessions: [FocusSession]
    let weeklyGoalHours: Double?
    let palette: InsightPalette.Colors
    let now: Date

    private var snapshot: FocusScoreSnapshot {
        analyzer.focusScore(sessions: sessions, weeklyGoalHours: weeklyGoalHours, now: now)
    }

    private var timeline: [FocusScoreSnapshot.DailyEntry] {
        snapshot.timeline.sorted { $0.dayStart < $1.dayStart }
    }

    var body: some View {
        let gradient = InsightPalette.gradient(for: palette)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MetricCapsules(metrics: summaryMetrics)

                focusTrend

                if !snapshot.components.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Score components")
                            .font(.headline)
                            .foregroundStyle(Color.white.opacity(0.9))
                        FocusScoreComponentRow(components: snapshot.components)
                    }
                }

                if !snapshot.bestHours.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prime focus windows")
                            .font(.headline)
                            .foregroundStyle(Color.white.opacity(0.9))
                        HStack(spacing: 10) {
                            ForEach(snapshot.bestHours.prefix(3), id: \.self) { hour in
                                Text(hourLabel(hour))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.85))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color.white.opacity(0.18), in: Capsule())
                            }
                        }
                    }
                }

                if !timeline.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily history")
                            .font(.headline)
                            .foregroundStyle(Color.white.opacity(0.9))
                        ForEach(timeline.reversed()) { entry in
                            FocusScoreHistoryRow(entry: entry)
                        }
                    }
                } else {
                    Text("Focus score history appears once you log a few sessions.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .background(gradient.ignoresSafeArea())
        .navigationTitle("Focus Score")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryMetrics: [Metric] {
        var items: [Metric] = [
            Metric(title: "Score", value: "\(snapshot.score)"),
            Metric(title: "Rating", value: snapshot.rating.rawValue)
        ]
        if let delta = snapshot.delta {
            let symbol = delta > 0 ? "+" : (delta < 0 ? "−" : "±")
            let amount = abs(delta)
            let label = delta == 0 ? "No change" : "\(symbol)\(amount) vs yesterday"
            items.append(Metric(title: "Change", value: label))
        }
        return items
    }

    @ViewBuilder
    private var focusTrend: some View {
        if timeline.isEmpty {
            Text("No history yet. Come back after you’ve logged more days.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Chart {
                ForEach(timeline) { entry in
                    LineMark(
                        x: .value("Day", entry.dayStart),
                        y: .value("Score", entry.score)
                    )
                    .foregroundStyle(Color.white.opacity(0.85))
                    PointMark(
                        x: .value("Day", entry.dayStart),
                        y: .value("Score", entry.score)
                    )
                    .symbolSize(32)
                    .foregroundStyle(Color.white)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel("\(value.as(Int.self) ?? 0)")
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .chartXAxis {
                AxisMarks(values: timeline.map(\.dayStart)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.weekday(.abbreviated))
                        }
                        .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
            }
            .frame(height: 220)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: comps) ?? now
        return Self.hourFormatter.string(from: date)
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("HH")
        return formatter
    }()
}

private struct FocusScoreComponentRow: View {
    let components: [FocusScoreSnapshot.Component]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(components) { component in
                FocusScoreComponentColumn(component: component)
            }
        }
    }
}

private struct FocusScoreHistoryRow: View {
    let entry: FocusScoreSnapshot.DailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.dayFormatter.string(from: entry.dayStart))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                Spacer()
                Text("\(entry.score)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }

            ProgressStripe(label: "Goal pace", ratio: entry.goalRatio)

            if let primeRatio = entry.primeRatio {
                ProgressStripe(label: "Prime time", ratio: primeRatio)
            }

            HStack(spacing: 6) {
                Text(String(format: "%.1fh actual", entry.actualHours))
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.65))
                Text("•")
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(String(format: "%.1fh target", entry.targetHours))
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private struct ProgressStripe: View {
        let label: String
        let ratio: Double

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.6))
                GeometryReader { geo in
                    let width = geo.size.width * CGFloat(min(max(ratio, 0), 1))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.75))
                            .frame(width: max(4, width))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

private struct InsightDetailView: View {
    let kind: InsightKind
    let palette: InsightPalette.Colors
    let sessions: [FocusSession]
    let analyzer: InsightsAnalyzer
    private let weekOffsets: [Int]
    private let baseNow: Date
    @State private var selectedWeek: Int

    init(kind: InsightKind, palette: InsightPalette.Colors, sessions: [FocusSession], analyzer: InsightsAnalyzer, now: Date = .now) {
        self.kind = kind
        self.palette = palette
        self.sessions = sessions
        self.analyzer = analyzer
        self.baseNow = now
        self.weekOffsets = analyzer.availableWeekOffsets(sessions: sessions, now: now)
        _selectedWeek = State(initialValue: 0)
    }

    private var summary: TemporalInsightsSummary {
        analyzer.summary(forWeekOffset: selectedWeek, sessions: sessions, now: baseNow)
    }

    var body: some View {
        let gradient = InsightPalette.gradient(for: palette)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WeekSelector(selectedWeek: $selectedWeek, weekOffsets: weekOffsets, summary: summary)

                switch kind {
                case .focusTotals:
                    focusContent(summary)
                case .satisfaction:
                    satisfactionContent(summary)
                case .consistency:
                    consistencyContent(summary)
                case .primeHours:
                    primeHoursContent(summary)
                case .rhythm:
                    rhythmContent(summary)
                }
            }
            .padding(20)
        }
        .background(gradient.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func focusContent(_ summary: TemporalInsightsSummary) -> some View {
        let snapshots = summary.dailySnapshots
        let maxSeconds = snapshots.map(\.totalSeconds).max() ?? 1

        MetricCapsules(metrics: [
            Metric(title: "Total", value: String(format: "%.1fh", summary.totalFocusSeconds / 3600)),
            Metric(title: "Sessions", value: "\(summary.sampleSessionCount)"),
            Metric(title: "Active days", value: "\(summary.activeDayCount)")
        ])

        Chart {
            ForEach(snapshots) { snapshot in
                BarMark(
                    x: .value("Day", snapshot.dayStart),
                    y: .value("Focus", snapshot.totalSeconds / 3600)
                )
                .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel(String(format: "%.0fh", value.as(Double.self) ?? 0))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .chartXAxis {
            AxisMarks(values: snapshots.map(\.dayStart)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.weekday(.abbreviated))
                    }
                    .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
        .frame(height: 200)

        VStack(alignment: .leading, spacing: 12) {
            Text("Daily breakdown")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.9))
            ForEach(snapshots) { snapshot in
                FocusDayRow(
                    label: weekdayLabel(snapshot.dayStart),
                    hours: snapshot.totalSeconds / 3600,
                    ratio: snapshot.totalSeconds / max(maxSeconds, 1)
                )
            }
        }
    }

    @ViewBuilder
    private func satisfactionContent(_ summary: TemporalInsightsSummary) -> some View {
        let moodPoints = summary.dailySnapshots.map { DailyMoodPoint(dayStart: $0.dayStart, score: $0.averageSatisfaction) }

        MetricCapsules(metrics: [
            Metric(title: "Average", value: summary.averageSatisfaction.map { String(format: "%.1f/10", $0) } ?? "—"),
            Metric(title: "Logged days", value: "\(moodPoints.filter { $0.score != nil }.count)")
        ])

        Chart {
            ForEach(moodPoints) { point in
                if let value = point.score {
                    LineMark(
                        x: .value("Day", point.dayStart),
                        y: .value("Mood", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.white.opacity(0.9))

                    PointMark(
                        x: .value("Day", point.dayStart),
                        y: .value("Mood", value)
                    )
                    .foregroundStyle(Color.white)
                }
            }
        }
        .chartYScale(domain: 0...10)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel(String(format: "%.0f", value.as(Double.self) ?? 0))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .chartXAxis {
            AxisMarks(values: moodPoints.map(\.dayStart)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.weekday(.abbreviated))
                    }
                    .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
        .frame(height: 200)

        Text("Mood entries help tailor your insights and upcoming widgets. Keep rating sessions to sharpen recommendations.")
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.7))
    }

    @ViewBuilder
    private func consistencyContent(_ summary: TemporalInsightsSummary) -> some View {
        MetricCapsules(metrics: [
            Metric(title: "Streak", value: "\(summary.dailyStreakCount) days"),
            Metric(title: "Active", value: "\(summary.activeDayCount)/\(summary.lookbackDays) days")
        ])

        VStack(alignment: .leading, spacing: 10) {
            ForEach(summary.dailySnapshots) { snapshot in
                HStack {
                    Text(weekdayLabel(snapshot.dayStart))
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.8))
                    Spacer()
                    if snapshot.totalSeconds > 0 {
                        Label(String(format: "%.1fh", snapshot.totalSeconds / 3600), systemImage: "checkmark.seal.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color.white)
                            .font(.footnote)
                    } else {
                        Label("Rest", systemImage: "moon")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color.white.opacity(0.6))
                            .font(.footnote)
                    }
                }
                .padding(.vertical, 4)
                Divider().overlay(Color.white.opacity(0.15))
            }
        }
    }

    @ViewBuilder
    private func primeHoursContent(_ summary: TemporalInsightsSummary) -> some View {
        MetricCapsules(metrics: [
            Metric(title: "Best window", value: summary.bestWindow.map(windowLabel) ?? "—"),
            Metric(title: "Top hour", value: summary.topHourMetrics.first.map { hourLabel($0.hour) } ?? "—")
        ])

        if summary.topHourMetrics.isEmpty {
            Text("Log more focus time to reveal your most reliable focus hours.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.7))
        } else {
            let maxSeconds = summary.topHourMetrics.map(\.totalSeconds).max() ?? 1
            VStack(alignment: .leading, spacing: 12) {
                ForEach(summary.topHourMetrics) { metric in
                    PrimeHourRow(
                        hourLabel: hourLabel(metric.hour),
                        ratio: metric.totalSeconds / maxSeconds,
                        duration: metric.totalSeconds
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func rhythmContent(_ summary: TemporalInsightsSummary) -> some View {
        MetricCapsules(metrics: [
            Metric(title: "Peak hour", value: summary.topHourMetrics.first.map { hourLabel($0.hour) } ?? "—"),
            Metric(title: "Total hours", value: String(format: "%.1f", summary.totalFocusSeconds / 3600))
        ])

        TimeOfDayChartView(
            metrics: summary.hourlyMetrics,
            highlightedHours: summary.bestWindow.map { Set($0.startHour ..< $0.endHour) } ?? [],
            lookbackDays: summary.lookbackDays,
            barColor: .white,
            labelColor: Color.white.opacity(0.7)
        )
        .padding(.top, 8)

        Text("This chart powers upcoming widgets like lock-screen glances. Keep logging to teach Monk your natural cadence.")
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.7))
    }

    private func weekdayLabel(_ date: Date) -> String {
        InsightDetailView.dayFormatter.string(from: date)
    }

    private func windowLabel(_ window: TemporalInsightsSummary.BestFocusWindow) -> String {
        "\(hourLabel(window.startHour)) – \(hourLabel(window.endHour))"
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        let formatter = InsightDetailView.hourFormatter
        let reference = Calendar(identifier: .gregorian).date(from: comps) ?? Date()
        return formatter.string(from: reference)
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private struct DailyMoodPoint: Identifiable {
        let dayStart: Date
        let score: Double?
        var id: Date { dayStart }
    }
}

private struct WeekSelector: View {
    @Binding var selectedWeek: Int
    let weekOffsets: [Int]
    let summary: TemporalInsightsSummary

    var body: some View {
        HStack(spacing: 12) {
            selectorButton(systemName: "chevron.left", disabled: selectedWeek >= maxOffset) {
                guard selectedWeek < maxOffset else { return }
                selectedWeek += 1
                Haptics.soft()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(weekLabel(for: summary))
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.9))
                Text(label(for: selectedWeek))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            selectorButton(systemName: "chevron.right", disabled: selectedWeek == 0) {
                guard selectedWeek > 0 else { return }
                selectedWeek -= 1
                Haptics.soft()
            }

            Menu {
                ForEach(weekOffsets, id: \.self) { offset in
                    Button {
                        guard selectedWeek != offset else { return }
                        selectedWeek = offset
                        Haptics.soft()
                    } label: {
                        Text(label(for: offset))
                    }
                }
            } label: {
                Image(systemName: "calendar")
                    .foregroundColor(.white.opacity(0.85))
                    .padding(8)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var maxOffset: Int { weekOffsets.max() ?? 0 }

    @ViewBuilder
    private func selectorButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundColor(disabled ? Color.white.opacity(0.25) : Color.white)
                .padding(8)
                .background(Color.white.opacity(disabled ? 0.08 : 0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(disabled)
    }

    private func weekLabel(for summary: TemporalInsightsSummary) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale.current
        formatter.dateTemplate = "MMM d"
        let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: summary.lookbackDays - 1, to: summary.weekStart) ?? summary.weekEnd
        return formatter.string(from: summary.weekStart, to: end)
    }

    private func label(for offset: Int) -> String {
        switch offset {
        case 0: return "This week"
        case 1: return "Last week"
        default: return "\(offset) weeks ago"
        }
    }
}

private struct MetricCapsules: View {
    let metrics: [Metric]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.65))
                    Text(metric.value)
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.92))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct Metric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct FocusDayRow: View {
    let label: String
    let hours: Double
    let ratio: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 34, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: geo.size.width * CGFloat(min(max(ratio, 0), 1)))
                }
            }
            .frame(height: 8)

            Text(String(format: "%.1fh", hours))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 44, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SatisfactionRow: View {
    let label: String
    let value: Double?

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 34, alignment: .leading)
            if let value {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: geo.size.width * CGFloat(min(max(value / 10, 0), 1)))
                    }
                }
                .frame(height: 8)
                Text(String(format: "%.1f", value))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 44, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PrimeHourRow: View {
    let hourLabel: String
    let ratio: Double
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 12) {
            Text(hourLabel)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 56, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(min(max(ratio, 0), 1)))
                }
            }
            .frame(height: 8)
            Text(String(format: "%.1fh", duration / 3600))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 44, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GoalDayRow: View {
    let label: String
    let actualHours: Double
    let targetHours: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 34, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(min(max(actualRatio, 0), 1)))
                    Capsule()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        .frame(width: geo.size.width * CGFloat(min(max(targetRatio, 0), 1)))
                }
            }
            .frame(height: 8)

            Text(String(format: "%.1fh", actualHours))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 44, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var actualRatio: Double {
        guard targetHours > 0 else { return 0 }
        return actualHours / max(targetHours * 1.6, targetHours)
    }

    private var targetRatio: Double {
        guard targetHours > 0 else { return 0 }
        return targetHours / max(targetHours * 1.6, targetHours)
    }
}

private struct TimeOfDayChartView: View {
    let metrics: [TemporalInsightsSummary.HourMetric]
    let highlightedHours: Set<Int>
    let lookbackDays: Int
    let barColor: Color
    let labelColor: Color

    var body: some View {
        if metrics.allSatisfy({ $0.totalSeconds <= 0 }) {
            Text("We’ll chart your focus rhythms once you have more sessions logged.")
                .font(.footnote)
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Chart(filteredMetrics) { metric in
                BarMark(
                    x: .value("Hour", metric.hour),
                    y: .value("Focus Hours", metric.totalSeconds / 3600)
                )
                .foregroundStyle(
                    highlightedHours.contains(metric.hour)
                        ? barColor
                        : barColor.opacity(0.35)
                )
                .cornerRadius(6)
            }
            .chartYScale(domain: 0...(maxHours + 0.5))
            .chartXAxis {
                AxisMarks(values: hourValues) { value in
                    if let hour = value.as(Int.self) {
                        AxisValueLabel {
                            Text(label(for: hour))
                        }
                        .foregroundStyle(labelColor)
                        .font(.caption2)
                    }
                    AxisGridLine()
                        .foregroundStyle(labelColor.opacity(0.18))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    if let hoursValue = value.as(Double.self) {
                        AxisValueLabel("\(Int(hoursValue))h")
                            .foregroundStyle(labelColor)
                            .font(.caption2)
                    }
                    AxisGridLine()
                        .foregroundStyle(labelColor.opacity(0.18))
                }
            }
            .chartLegend(.hidden)
            .frame(height: 180)

            Text("Aggregated across the last \(lookbackDays) days.")
                .font(.caption2)
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filteredMetrics: [TemporalInsightsSummary.HourMetric] {
        metrics.filter { $0.totalSeconds > 0 || highlightedHours.contains($0.hour) }
    }

    private var hourValues: [Int] {
        Array(Set(filteredMetrics.map(\.hour))).sorted()
    }

    private var maxHours: Double {
        let maxSeconds = filteredMetrics.map(\.totalSeconds).max() ?? 0
        return maxSeconds / 3600
    }

    private func label(for hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        let formatter = TimeOfDayChartView.hourFormatter
        let date = Calendar(identifier: .gregorian).date(from: comps) ?? Date()
        return formatter.string(from: date)
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter
    }()
}
