import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsList: [Preferences]

    private var prefs: Preferences? { prefsList.first }

    enum Mode: String, CaseIterable, Identifiable { case daily = "Daily", weekly = "Weekly"; var id: String { rawValue } }
    @State private var mode: Mode = .daily
    @State private var dailyDate: Date = Date()
    @State private var windowDays: Int = 14
    @State private var streakCount: Int = 0
    @State private var daySheet: DaySelection? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatingBackground(base: Theme.dataBackground(), halo: Theme.dataHaloGradient)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Picker("Mode", selection: $mode) {
                            ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                        }
                        .pickerStyle(.segmented)

                        if mode == .daily {
                            HStack {
                                DatePicker("Day", selection: $dailyDate, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                Spacer()
                            }
                            DailyTimelineBarView(day: dailyDate)
                                .frame(height: 36)
                                .padding(.top, 8)
                        } else {
                            ChartView(windowDays: windowDays, weeklyGoalHours: prefs?.weeklyGoalHours ?? 0, onSelectDay: { date in
                                let dayStart = Calendar(identifier: .gregorian).startOfDay(for: date)
                                daySheet = DaySelection(dayStart: dayStart)
                            }) { totals in
                                computeStreak(from: totals, weeklyGoal: prefs?.weeklyGoalHours ?? 0)
                            }
                            Picker("Range", selection: $windowDays) {
                                Text("7 days").tag(7)
                                Text("14 days").tag(14)
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 8)
                        }

                        if let weeklyGoal = prefs?.weeklyGoalHours, weeklyGoal > 0 {
                            HStack {
                                Image(systemName: "flag")
                                Text("Weekly goal: ")
                                Text(String(format: "%.0f h", weeklyGoal))
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }

                        if mode == .weekly {
                            HStack {
                                Image(systemName: "flame")
                                Text("Streak: ")
                                Text("\(streakCount) weeks")
                                    .bold()
                                Spacer()
                            }
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 36)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("Data")
            .sheet(item: $daySheet) { DayDetailView(dayStart: $0.dayStart) }
        }
    }
}

#Preview {
    InsightsView()
}

// MARK: - Chart

private struct ChartView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt)]) private var sessions: [FocusSession]
    let windowDays: Int
    let weeklyGoalHours: Double
    var onSelectDay: (Date) -> Void = { _ in }
    var onData: (([DayTotal]) -> Void)? = nil

    var body: some View {
        let rows = data
        VStack(alignment: .leading) {
            WeeklyBars(rows: rows, dailyGoalHours: weeklyGoalHours / 7.0, onSelect: onSelectDay)
                .frame(height: 220)
        }
        .task { onData?(rows) }
        .task(id: changeSignature) { onData?(data) }
    }

    private var data: [DayTotal] {
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.startOfDay(for: now).addingTimeInterval(24*60*60)
        guard let start = calendar.date(byAdding: .day, value: -windowDays + 1, to: end) else { return [] }

        var buckets: [Date: TimeInterval] = [:]
        for s in sessions where s.startedAt < end && (s.endedAt == nil || s.endedAt! >= start) {
            let sStart = max(s.startedAt, start)
            let sEnd = min(s.endedAt ?? now, end)
            guard sEnd > sStart else { continue }
            for part in DateUtils.splitByDay(start: sStart, end: sEnd) {
                buckets[part.dayStart, default: 0] += part.seconds
            }
        }

        // Ensure all days in window appear, even if zero
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            _ = buckets[dayStart, default: 0]
            cursor = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        }

        return buckets
            .map { DayTotal(dayStart: $0.key, hours: $0.value / 3600.0) }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private var sessionsSignature: String {
        sessions.map { $0.id.uuidString + ":" + String($0.startedAt.timeIntervalSince1970) + ":" + String($0.endedAt?.timeIntervalSince1970 ?? -1) }.joined(separator: "|")
    }

    private var changeSignature: String {
        return "\(sessionsSignature)|wd=\(windowDays)|wg=\(weeklyGoalHours)"
    }
}

private struct DayTotal: Identifiable {
    var id: Date { dayStart }
    let dayStart: Date
    let hours: Double
}

private struct DaySelection: Identifiable { let dayStart: Date; var id: Date { dayStart } }

// Handle bar selection via tap; use chart overlay when available
private struct SelectionTapModifier: ViewModifier {
    let data: [DayTotal]
    let onSelect: (Date) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(Color.clear).contentShape(Rectangle()).onTapGesture { location in
                            if let plotAnchor = proxy.plotFrame {
                                let frame = geo[plotAnchor]
                                let x = location.x - frame.origin.x
                                let y = location.y - frame.origin.y
                                // Try both axes for date depending on chart orientation
                                let cal = Calendar(identifier: .gregorian)
                                if let dateX: Date = proxy.value(atX: x) {
                                    onSelect(cal.startOfDay(for: dateX))
                                } else if let dateY: Date = proxy.value(atY: y) {
                                    onSelect(cal.startOfDay(for: dateY))
                                }
                            }
                        }
                    }
                }
        } else {
            content
        }
    }
}

private struct WeeklyBars: View {
    let rows: [DayTotal]
    let dailyGoalHours: Double
    let onSelect: (Date) -> Void

    var body: some View {
        Chart {
            ForEach(rows) { item in
                BarMark(
                    x: .value("Hours", item.hours as Double),
                    y: .value("Day", item.dayStart, unit: .day)
                )
            }
            if dailyGoalHours > 0 {
                RuleMark(x: .value("Goal", dailyGoalHours as Double))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .modifier(SelectionTapModifier(data: rows, onSelect: onSelect))
        .chartYAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
    }
}

// MARK: - Daily single-bar timeline (sleep-style)

private struct DailyTimelineBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt)]) private var sessions: [FocusSession]
    let day: Date

    var body: some View {
        let cal = Calendar(identifier: .gregorian)
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let segs = segments(dayStart: dayStart, dayEnd: dayEnd)

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 14)
                ForEach(segs.indices, id: \.self) { i in
                    let seg = segs[i]
                    let total = dayEnd.timeIntervalSince(dayStart)
                    let startFrac = seg.start.timeIntervalSince(dayStart) / total
                    let widthFrac = max(0, seg.end.timeIntervalSince(seg.start) / total)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(seg.color)
                        .frame(width: max(1, geo.size.width * widthFrac), height: 14)
                        .offset(x: geo.size.width * startFrac)
                        .accessibilityLabel("Focus segment")
                }
            }
        }
        .frame(height: 14)
    }

    private func segments(dayStart: Date, dayEnd: Date) -> [TimelineSegment] {
        let now = Date()
        let filtered = sessions.filter { $0.startedAt < dayEnd && ($0.endedAt ?? now) > dayStart }
        var intervals: [(start: Date, end: Date, color: Color)] = []
        for s in filtered {
            let start = max(s.startedAt, dayStart)
            let end = min(s.endedAt ?? now, dayEnd)
            guard end > start else { continue }
            intervals.append((start, end, color(for: s)))
        }
        intervals.sort { $0.start < $1.start }
        var result: [TimelineSegment] = []
        for iv in intervals {
            if var last = result.last, iv.start <= last.end {
                last.end = max(last.end, iv.end)
                result[result.count - 1] = last
            } else {
                result.append(TimelineSegment(start: iv.start, end: iv.end, color: iv.color))
            }
        }
        return result
    }

    private func color(for session: FocusSession) -> Color {
        if let project = session.project {
            let gradient = ProjectPalette.shared.gradient(for: project.gradientIndex)
            return gradient.start
        }
        return Color.cyan.opacity(0.9)
    }
}

private struct TimelineSegment {
    var start: Date
    var end: Date
    var color: Color
}

private struct ProjectPalette {
    static let shared = ProjectPalette()
    private init() {}

    private let gradients: [(start: Color, end: Color)] = [
        (Color(red: 0.27, green: 0.56, blue: 0.99), Color(red: 0.60, green: 0.28, blue: 0.98)),
        (Color(red: 0.33, green: 0.76, blue: 0.86), Color(red: 0.20, green: 0.48, blue: 0.97)),
        (Color(red: 0.99, green: 0.62, blue: 0.45), Color(red: 0.95, green: 0.30, blue: 0.55)),
        (Color(red: 0.98, green: 0.80, blue: 0.36), Color(red: 0.96, green: 0.48, blue: 0.31)),
        (Color(red: 0.54, green: 0.43, blue: 0.99), Color(red: 0.28, green: 0.21, blue: 0.58)),
        (Color(red: 0.34, green: 0.64, blue: 0.99), Color(red: 0.22, green: 0.30, blue: 0.64)),
        (Color(red: 0.99, green: 0.45, blue: 0.69), Color(red: 0.58, green: 0.32, blue: 0.93)),
        (Color(red: 0.46, green: 0.35, blue: 0.82), Color(red: 0.19, green: 0.18, blue: 0.38))
    ]

    func gradient(for index: Int) -> (start: Color, end: Color) {
        guard !gradients.isEmpty else { return (.cyan, .blue) }
        let safe = ((index % gradients.count) + gradients.count) % gradients.count
        return gradients[safe]
    }
}

// Day detail list
private struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let dayStart: Date

    var body: some View {
        let cal = Calendar(identifier: .gregorian)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: dayStart))!
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { s in s.startedAt < dayEnd && (s.endedAt == nil || s.endedAt! >= dayStart) },
            sortBy: [SortDescriptor<FocusSession>(\.startedAt)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []

        return NavigationStack {
            List {
                ForEach(sessions) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.startedAt, style: .time)
                            Text("–")
                            Text((s.endedAt ?? Date()), style: .time)
                            Spacer()
                            Text(durationString(s, in: dayStart))
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        }
                        if let project = s.project {
                            Text(project.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(Text(dayStart, format: .dateTime.weekday(.wide).day().month()))
        }
    }

    private func durationString(_ s: FocusSession, in day: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let start = max(s.startedAt, cal.startOfDay(for: day))
        let end = min(s.endedAt ?? Date(), cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day))!)
        let sec = max(0, end.timeIntervalSince(start))
        return String(format: "%.2f h", sec / 3600)
    }
}

private extension InsightsView {
    func computeStreak(from totals: [DayTotal], weeklyGoal: Double) {
        guard weeklyGoal > 0 else { streakCount = 0; return }
        let sorted = totals.sorted { $0.dayStart < $1.dayStart }
        var count = 0
        var index = sorted.count
        while index >= 7 {
            let chunk = sorted[index - 7..<index]
            let totalHours = chunk.reduce(0) { $0 + $1.hours }
            if totalHours + 1e-9 >= weeklyGoal {
                count += 1
                index -= 7
            } else {
                break
            }
        }
        streakCount = count
    }
}
