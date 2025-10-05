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
    @State private var availableTags: [String] = []
    @State private var selectedTags: Set<String> = []
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

                        TagFilterView(available: availableTags, selected: $selectedTags)
                            .onAppear { loadAvailableTags() }
                            .onChange(of: windowDays) { _, _ in loadAvailableTags() }

                        if mode == .daily {
                            HStack {
                                DatePicker("Day", selection: $dailyDate, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                Spacer()
                            }
                            DailyTimelineBarView(day: dailyDate, selectedTags: selectedTags)
                                .frame(height: 36)
                                .padding(.top, 8)
                        } else {
                            ChartView(windowDays: windowDays, weeklyGoalHours: prefs?.weeklyGoalHours ?? 0, selectedTags: selectedTags, onSelectDay: { date in
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
                .onAppear { loadAvailableTags() }
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
    let selectedTags: Set<String>
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

        var filtered = sessions
        if !selectedTags.isEmpty {
            filtered = filtered.filter { !Set($0.tags).isDisjoint(with: selectedTags) }
        }

        var buckets: [Date: TimeInterval] = [:]
        for s in filtered where s.startedAt < end && (s.endedAt == nil || s.endedAt! >= start) {
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
        let tagSig = selectedTags.sorted().joined(separator: ",")
        return "\(sessionsSignature)|wd=\(windowDays)|tags=\(tagSig)|wg=\(weeklyGoalHours)"
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
    let selectedTags: Set<String>

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
        var filtered = sessions.filter { $0.startedAt < dayEnd && ($0.endedAt ?? now) > dayStart }
        if !selectedTags.isEmpty {
            filtered = filtered.filter { !Set($0.tags).isDisjoint(with: selectedTags) }
        }
        // Map to clamped intervals with a primary tag for color
        var intervals: [(start: Date, end: Date, tag: String)] = []
        for s in filtered {
            let start = max(s.startedAt, dayStart)
            let end = min(s.endedAt ?? now, dayEnd)
            guard end > start else { continue }
            let tag = s.tags.first ?? "Focus"
            intervals.append((start, end, tag))
        }
        // Sort and merge overlapping by preferring earlier start (coalesce same tag contiguous)
        intervals.sort { $0.start < $1.start }
        var result: [TimelineSegment] = []
        for iv in intervals {
            let color = colorForTag(iv.tag)
            if var last = result.last, iv.start <= last.end { // overlap or touch
                // Extend the last segment end to cover overlap; keep last color
                last.end = max(last.end, iv.end)
                result[result.count - 1] = last
            } else {
                result.append(TimelineSegment(start: iv.start, end: iv.end, color: color))
            }
        }
        return result
    }

    private func colorForTag(_ tag: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .cyan, .yellow]
        let idx = abs(tag.hashValue) % palette.count
        return palette[idx]
    }
}

private struct TimelineSegment {
    var start: Date
    var end: Date
    var color: Color
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
                        // Note removed from model; only show tags now
                        if !s.tags.isEmpty {
                            Text("#" + s.tags.joined(separator: " #"))
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

// MARK: - Daily stacked per hour by tag

private struct HourlyStackedChartView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt)]) private var sessions: [FocusSession]
    let day: Date
    let selectedTags: Set<String>

    @State private var pageIndex: Int = 0

    var body: some View {
        TabView(selection: $pageIndex) {
            ForEach(0..<2, id: \.self) { idx in
                let startHour = (idx == 0) ? 0 : 8
                page(startHour: startHour)
                    .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
    }

    @ViewBuilder
    private func page(startHour: Int) -> some View {
        let cal = Calendar(identifier: .gregorian)
        let dayStart = cal.startOfDay(for: day)
        let windowStart = cal.date(byAdding: .hour, value: startHour, to: dayStart)!
        let windowEnd = cal.date(byAdding: .hour, value: min(startHour + 16, 24), to: dayStart)!
        let bins = computeData().filter { $0.hourStart >= windowStart && $0.hourStart < windowEnd }

        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(bins) { item in
                    BarMark(
                        x: .value("Hour", item.hourStart, unit: .hour),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(by: .value("Tag", item.tag))
                    .opacity(item.minutes > 0 ? 1 : 0)
                }
            }
            .chartXScale(domain: windowStart...windowEnd)
            .chartYScale(domain: 0...60)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { value in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                }
            }
            .chartLegend(.automatic)
        }
        .padding(.horizontal, 2)
    }

    private func computeData() -> [HourTagBin] {
        let cal = Calendar(identifier: .gregorian)
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let now = Date()

        var filtered = sessions.filter { $0.startedAt < dayEnd && ($0.endedAt ?? now) > dayStart }
        if !selectedTags.isEmpty {
            filtered = filtered.filter { !Set($0.tags).isDisjoint(with: selectedTags) }
        }

        // Prepare all hours and tag set
        var tagSet = Set<String>()
        for s in filtered { tagSet.formUnion(s.tags) }
        if tagSet.isEmpty { tagSet.insert("Untagged") }

        // Initialize buckets: hour -> tag -> seconds
        var buckets: [Date: [String: TimeInterval]] = [:]
        for h in 0..<24 {
            let hStart = cal.date(byAdding: .hour, value: h, to: dayStart)!
            buckets[hStart] = [:]
        }

        for s in filtered {
            let sStart = max(s.startedAt, dayStart)
            let sEnd = min(s.endedAt ?? now, dayEnd)
            guard sEnd > sStart else { continue }
            let tags = s.tags.isEmpty ? ["Untagged"] : s.tags
            let share = 1.0 / Double(tags.count)
            // Iterate hours overlapping the session
            var hCursor = cal.dateInterval(of: .hour, for: sStart)!.start
            while hCursor < sEnd {
                let hEnd = cal.date(byAdding: .hour, value: 1, to: hCursor)!
                let segStart = max(hCursor, sStart)
                let segEnd = min(hEnd, sEnd)
                if segEnd > segStart {
                    let seconds = segEnd.timeIntervalSince(segStart) * share
                    for tag in tags {
                        buckets[hCursor, default: [:]][tag, default: 0] += seconds
                    }
                }
                hCursor = hEnd
            }
        }

        // Map to bins in minutes
        var bins: [HourTagBin] = []
        for (hStart, tagDict) in buckets {
            for tag in tagSet {
                let sec = tagDict[tag] ?? 0
                let minutes = sec / 60.0
                bins.append(HourTagBin(hourStart: hStart, tag: tag, minutes: minutes))
            }
        }
        return bins.sorted { lhs, rhs in
            if lhs.hourStart == rhs.hourStart { return lhs.tag < rhs.tag }
            return lhs.hourStart < rhs.hourStart
        }
    }
}

private struct HourTagBin: Identifiable {
    var id: String { "\(hourStart.timeIntervalSince1970)-\(tag)" }
    let hourStart: Date
    let tag: String
    let minutes: Double
}

// MARK: - Tag Filter & Streaks

private struct TagFilterView: View {
    let available: [String]
    @Binding var selected: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SelectableChip(title: "All", isSelected: selected.isEmpty) {
                    selected.removeAll()
                }
                ForEach(available, id: \.self) { tag in
                    SelectableChip(title: "#\(tag)", isSelected: selected.contains(tag)) {
                        if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension InsightsView {
    func loadAvailableTags(now: Date = .now) {
        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.startOfDay(for: now).addingTimeInterval(24*60*60)
        guard let start = calendar.date(byAdding: .day, value: -windowDays + 1, to: end) else { return }
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { s in
                s.startedAt < end && (s.endedAt == nil || s.endedAt! >= start)
            }
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        let tags = Set(sessions.flatMap { $0.tags })
        availableTags = Array(tags).sorted()
        selectedTags = selectedTags.intersection(tags)
    }

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
