import Foundation

struct TemporalInsightsSummary {
    struct HourMetric: Identifiable {
        let hour: Int
        let totalSeconds: TimeInterval
        let averageSatisfaction: Double?

        var id: Int { hour }
    }

    struct BestFocusWindow {
        let startHour: Int
        let endHour: Int
        let totalSeconds: TimeInterval
        let averageSatisfaction: Double?
    }

    struct DaySnapshot: Identifiable {
        let dayStart: Date
        let totalSeconds: TimeInterval
        let averageSatisfaction: Double?
        let sessionCount: Int

        var id: Date { dayStart }
    }

    let weekStart: Date
    let weekEnd: Date
    let lookbackDays: Int
    let totalFocusSeconds: TimeInterval
    let sampleSessionCount: Int
    let averageSatisfaction: Double?
    let dailyStreakCount: Int
    let hourlyMetrics: [HourMetric]
    let topHourMetrics: [HourMetric]
    let bestWindow: BestFocusWindow?
    let dailySnapshots: [DaySnapshot]
    let activeDayCount: Int
    let dailyHourlyTotals: [Date: [Int: TimeInterval]]
}

struct FocusScoreSnapshot {
    struct Component: Identifiable {
        enum Kind {
            case goalPace
            case primeAlignment
        }

        let kind: Kind
        let title: String
        let weight: Double
        let normalizedValue: Double
        let points: Double
        let actualValue: Double
        let targetValue: Double?
        let hasData: Bool

        var id: Kind { kind }
        var maxPoints: Double { weight * 100 }
        var progressFraction: Double {
            guard maxPoints > 0 else { return 0 }
            return max(0, min(points / maxPoints, 1))
        }
    }

    struct DailyEntry: Identifiable {
        let dayStart: Date
        let score: Int
        let goalRatio: Double
        let primeRatio: Double?
        let actualHours: Double
        let targetHours: Double
        let actualPrimeHours: Double
        let expectedPrimeHours: Double

        var id: Date { dayStart }
    }

    enum Rating: String {
        case peakFlow = "Peak Flow"
        case strongFocus = "Strong Focus"
        case stable = "Stable"
        case distracted = "Distracted"
        case unfocused = "Unfocused"

        init(score: Int) {
            switch score {
            case 90...: self = .peakFlow
            case 75..<90: self = .strongFocus
            case 60..<75: self = .stable
            case 40..<60: self = .distracted
            default: self = .unfocused
            }
        }
    }

    let score: Int
    let rating: Rating
    let delta: Int?
    let components: [Component]
    let today: DailyEntry?
    let timeline: [DailyEntry]
    let bestHours: [Int]
    let dailyTargetHours: Double
    let hasPrimeData: Bool
    let weeklyProjection: WeeklyGoalProjection?
    let dynamicTodayGoalHours: Double?

    var hasData: Bool {
        if today != nil { return true }
        return hasPrimeData
    }

    var todayActualHours: Double {
        if let projection = weeklyProjection {
            return projection.todayActualHours
        }
        return today?.actualHours ?? 0
    }

    var todayRecommendedHours: Double {
        if let projection = weeklyProjection {
            return projection.todayRecommendedHours
        }
        return dailyTargetHours
    }

    var todayAdditionalHoursNeeded: Double {
        if let dynamicGoal = dynamicTodayGoalHours {
            let diff = dynamicGoal - todayActualHours
            return diff > 0 ? diff : 0
        }
        if let projection = weeklyProjection {
            return projection.todayAdditionalHoursNeeded
        }
        let diff = todayRecommendedHours - todayActualHours
        return diff > 0 ? diff : 0
    }

    var weeklyGoalHours: Double? { weeklyProjection?.goalHours }
    var weeklyActualHours: Double? { weeklyProjection?.actualHours }
    var weeklyRemainingHours: Double? { weeklyProjection?.remainingHours }
}

struct WeeklyGoalProjection {
    struct DayPlan: Identifiable {
        let dayStart: Date
        let actualHours: Double
        let plannedHours: Double
        let isFuture: Bool

        var id: Date { dayStart }
    }

    let goalHours: Double
    let actualHours: Double
    let completionFraction: Double
    let remainingHours: Double
    let remainingDays: Int
    let recommendedDailyHours: Double
    let todayActualHours: Double
    let todayRecommendedHours: Double
    let todayAdditionalHoursNeeded: Double
    let primeHourLabels: [String]
    let dayPlans: [DayPlan]
}

struct WeeklyProjectGoalSummary {
    struct Segment: Identifiable {
        let id: UUID
        let title: String
        let gradientIndex: Int
        let goalHours: Double
        let actualHours: Double

        var progressFraction: Double {
            guard goalHours > 0 else { return 0 }
            return min(max(actualHours / goalHours, 0), 1)
        }
    }

    let weekStart: Date
    let weekEnd: Date
    let rawGoalHours: Double
    let totalGoalHours: Double
    let scaleFactor: Double
    let segments: [Segment]

    var totalActualHours: Double {
        segments.reduce(0) { $0 + $1.actualHours }
    }

    var hasGoals: Bool {
        totalGoalHours > 0 && !segments.isEmpty
    }
}

struct TemporalInsightsConfig {
    var lookbackDays: Int = 7
    var bestWindowWidthHours: Int = 2
}

struct InsightsAnalyzer {
    private let calendar: Calendar

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    func summarize(sessions: [FocusSession], now: Date = .now, config: TemporalInsightsConfig = TemporalInsightsConfig()) -> TemporalInsightsSummary {
        let lookbackStart = lookbackAnchor(for: now, days: config.lookbackDays)
        guard let lookbackEnd = calendar.date(byAdding: .day, value: config.lookbackDays, to: lookbackStart) else {
            return TemporalInsightsSummary(
                weekStart: lookbackStart,
                weekEnd: lookbackStart,
                lookbackDays: config.lookbackDays,
                totalFocusSeconds: 0,
                sampleSessionCount: 0,
                averageSatisfaction: nil,
                dailyStreakCount: 0,
                hourlyMetrics: [],
                topHourMetrics: [],
                bestWindow: nil,
                dailySnapshots: [],
                activeDayCount: 0,
                dailyHourlyTotals: [:]
            )
        }

        var totalSeconds: TimeInterval = 0
        var sampleCount = 0
        var hourlyTotals: [Int: TimeInterval] = [:]
        var dailyHourlyTotals: [Date: [Int: TimeInterval]] = [:]

        var dailyTotals: [Date: TimeInterval] = [:]
        var dailySessionIds: [Date: Set<UUID>] = [:]

        for session in sessions {
            let sessionEnd = (session.endedAt ?? now)
            guard sessionEnd > lookbackStart, session.startedAt < lookbackEnd else { continue }

            let clippedStart = max(session.startedAt, lookbackStart)
            let clippedEnd = min(sessionEnd, lookbackEnd)
            guard clippedEnd > clippedStart else { continue }

            let duration = clippedEnd.timeIntervalSince(clippedStart)
            guard duration > 0 else { continue }
            totalSeconds += duration
            sampleCount += 1

            accumulateHourlyMetrics(
                start: clippedStart,
                end: clippedEnd,
                totals: &hourlyTotals,
                dailyHourTotals: &dailyHourlyTotals
            )

            for part in DateUtils.splitByDay(start: clippedStart, end: clippedEnd, calendar: calendar) {
                guard part.seconds > 0 else { continue }
                dailyTotals[part.dayStart, default: 0] += part.seconds
                dailySessionIds[part.dayStart, default: []].insert(session.id)
            }
        }

        let hourlyMetrics = (0..<24).map { hour -> TemporalInsightsSummary.HourMetric in
            let total = hourlyTotals[hour] ?? 0
            return TemporalInsightsSummary.HourMetric(hour: hour, totalSeconds: total, averageSatisfaction: nil)
        }

        let bestWindow = selectBestWindow(from: hourlyMetrics, hours: config.bestWindowWidthHours)
        let topHourMetrics = hourlyMetrics
            .filter { $0.totalSeconds > 0 }
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(3)

        let allDayStarts: [Date] = (0..<config.lookbackDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: lookbackStart)
        }

        let dailySnapshots: [TemporalInsightsSummary.DaySnapshot] = allDayStarts.map { dayStart in
            let total = dailyTotals[dayStart] ?? 0
            let sessionCount = dailySessionIds[dayStart]?.count ?? 0
            return TemporalInsightsSummary.DaySnapshot(
                dayStart: dayStart,
                totalSeconds: total,
                averageSatisfaction: nil,
                sessionCount: sessionCount
            )
        }

        let activeDayCount = dailySnapshots.filter { $0.totalSeconds > 0 }.count
        let dayBuckets = Set(dailySnapshots.filter { $0.totalSeconds > 0 }.map(\.dayStart))
        let streak = dailyStreakCount(from: dayBuckets)

        return TemporalInsightsSummary(
            weekStart: lookbackStart,
            weekEnd: lookbackEnd,
            lookbackDays: config.lookbackDays,
            totalFocusSeconds: totalSeconds,
            sampleSessionCount: sampleCount,
            averageSatisfaction: nil,
            dailyStreakCount: streak,
            hourlyMetrics: hourlyMetrics,
            topHourMetrics: Array(topHourMetrics),
            bestWindow: bestWindow,
            dailySnapshots: dailySnapshots,
            activeDayCount: activeDayCount,
            dailyHourlyTotals: dailyHourlyTotals
        )
    }

    func summary(forWeekOffset offset: Int,
                 sessions: [FocusSession],
                 now: Date = .now,
                 config: TemporalInsightsConfig = TemporalInsightsConfig()) -> TemporalInsightsSummary {
        guard let shiftedNow = calendar.date(byAdding: .day, value: -7 * offset, to: now) else {
            return summarize(sessions: sessions, now: now, config: config)
        }
        return summarize(sessions: sessions, now: shiftedNow, config: config)
    }

    func focusScore(sessions: [FocusSession],
                    weeklyGoalHours: Double?,
                    now: Date = .now,
                    fallbackWeeklyGoal: Double = 0) -> FocusScoreSnapshot {
        let config = TemporalInsightsConfig(lookbackDays: 14)
        let hasGoal = (weeklyGoalHours ?? 0) > 0
        let goalSessions = hasGoal
            ? sessions.filter { ($0.project?.weeklyGoalHours ?? 0) > 0 }
            : sessions
        let summary = summarize(sessions: goalSessions, now: now, config: config)
        let dailyTargetHours = max((weeklyGoalHours ?? fallbackWeeklyGoal) / 7, 0)
        let dailyTargetSeconds = dailyTargetHours * 3600
        let activeDayDivisor = max(1, summary.activeDayCount)

        let primeHours = summary.hourlyMetrics
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(4)
            .map(\.hour)
        let primeHourSet = Set(primeHours)

        var expectedPrimePerHour: [Int: TimeInterval] = [:]
        for hour in primeHours {
            if let metric = summary.hourlyMetrics.first(where: { $0.hour == hour }) {
                expectedPrimePerHour[hour] = metric.totalSeconds / Double(activeDayDivisor)
            }
        }

        let weights = (goal: 0.65, prime: 0.35)
        var entries: [FocusScoreSnapshot.DailyEntry] = []

        for snapshot in summary.dailySnapshots {
            let actualSeconds = snapshot.totalSeconds
            let goalRatio: Double
            if dailyTargetSeconds > 0 {
                goalRatio = actualSeconds / dailyTargetSeconds
            } else {
                goalRatio = actualSeconds > 0 ? 1 : 0
            }

            let hourlyMap = summary.dailyHourlyTotals[snapshot.dayStart] ?? [:]
            let actualPrimeSeconds = primeHourSet.reduce(0) { $0 + (hourlyMap[$1] ?? 0) }
            let expectedPrimeSeconds = primeHourSet.reduce(0) { $0 + (expectedPrimePerHour[$1] ?? 0) }

            let primeRatio: Double?
            if expectedPrimeSeconds > 0 {
                primeRatio = actualPrimeSeconds / expectedPrimeSeconds
            } else if actualSeconds > 0 {
                primeRatio = 1
            } else {
                primeRatio = nil
            }

            let normalizedGoal = min(max(goalRatio, 0), 1)
            let normalizedPrime: Double
            if let primeRatio {
                normalizedPrime = min(max(primeRatio, 0), 1)
            } else {
                normalizedPrime = 0
            }

            let composite = (weights.goal * normalizedGoal) + (weights.prime * normalizedPrime)
            let score = Int(round(composite * 100))

            let entry = FocusScoreSnapshot.DailyEntry(
                dayStart: snapshot.dayStart,
                score: score,
                goalRatio: goalRatio,
                primeRatio: primeRatio,
                actualHours: actualSeconds / 3600,
                targetHours: dailyTargetHours,
                actualPrimeHours: actualPrimeSeconds / 3600,
                expectedPrimeHours: expectedPrimeSeconds / 3600
            )
            entries.append(entry)
        }

        let todayEntry = entries.last
        let previousEntry = entries.dropLast().last
        let delta = todayEntry.flatMap { today in previousEntry.map { today.score - $0.score } }

        let components: [FocusScoreSnapshot.Component]
        if let todayEntry {
            let goalNormalized = min(max(todayEntry.goalRatio, 0), 1)
            let primeHasData = todayEntry.primeRatio != nil
            let primeNormalized: Double
            if let primeRatio = todayEntry.primeRatio {
                primeNormalized = min(max(primeRatio, 0), 1)
            } else {
                primeNormalized = 0
            }

            components = [
                .init(
                    kind: .goalPace,
                    title: "Goal Pace",
                    weight: weights.goal,
                    normalizedValue: goalNormalized,
                    points: weights.goal * goalNormalized * 100,
                    actualValue: todayEntry.actualHours,
                    targetValue: dailyTargetHours,
                    hasData: dailyTargetHours > 0
                ),
                .init(
                    kind: .primeAlignment,
                    title: "Prime Hours",
                    weight: weights.prime,
                    normalizedValue: primeNormalized,
                    points: weights.prime * primeNormalized * 100,
                    actualValue: todayEntry.actualPrimeHours,
                    targetValue: todayEntry.expectedPrimeHours,
                    hasData: primeHasData
                )
            ]
        } else {
            components = []
        }

        let weeklyProjection = weeklyGoalProjection(sessions: goalSessions, weeklyGoalHours: weeklyGoalHours, now: now)
        let dynamicTodayGoalHours = weeklyProjection.flatMap { projection -> Double? in
            guard let weeklyGoalHours else { return nil }
            let remainingHours = max(0, weeklyGoalHours - projection.actualHours)
            guard remainingHours > 0 else { return 0 }
            let todayStart = calendar.startOfDay(for: now)
            guard let nextSunday = calendar.nextDate(after: todayStart,
                                                     matching: DateComponents(weekday: 1),
                                                     matchingPolicy: .nextTimePreservingSmallerComponents) else {
                return nil
            }

            var days = 0
            var cursor = todayStart
            while cursor < nextSunday {
                // Skip upcoming Sunday itself, but include today even if Sunday.
                if calendar.component(.weekday, from: cursor) != 1 || calendar.isDate(cursor, inSameDayAs: todayStart) {
                    days += 1
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = nextDay
            }

            let divisor = max(1, days)
            return remainingHours / Double(divisor)
        }

        return FocusScoreSnapshot(
            score: todayEntry?.score ?? 0,
            rating: FocusScoreSnapshot.Rating(score: todayEntry?.score ?? 0),
            delta: delta,
            components: components,
            today: todayEntry,
            timeline: entries,
            bestHours: Array(primeHourSet).sorted(),
            dailyTargetHours: dailyTargetHours,
            hasPrimeData: expectedPrimePerHour.values.contains(where: { $0 > 0 }),
            weeklyProjection: weeklyProjection,
            dynamicTodayGoalHours: dynamicTodayGoalHours
        )
    }

    func weeklyGoalProjection(sessions: [FocusSession],
                              weeklyGoalHours: Double?,
                              now: Date = .now) -> WeeklyGoalProjection? {
        guard let weeklyGoalHours, weeklyGoalHours > 0 else { return nil }

        let weekConfig = TemporalInsightsConfig(lookbackDays: 7)
        let weekSummary = summarize(sessions: sessions, now: now, config: weekConfig)
        let extendedSummary = summarize(sessions: sessions, now: now, config: TemporalInsightsConfig(lookbackDays: 14))

        let daySnapshots = weekSummary.dailySnapshots.sorted { $0.dayStart < $1.dayStart }
        let totalGoalSeconds = weeklyGoalHours * 3600
        let totalActualSeconds = daySnapshots.reduce(0) { $0 + $1.totalSeconds }
        let completionFraction = totalGoalSeconds > 0 ? min(1, totalActualSeconds / totalGoalSeconds) : 0
        let baselineDailyHours = weeklyGoalHours / Double(max(1, daySnapshots.count))

        let todayStart = calendar.startOfDay(for: now)
        let todaysSnapshot = daySnapshots.first { calendar.isDate($0.dayStart, inSameDayAs: todayStart) }
        let todaysActualSeconds = todaysSnapshot?.totalSeconds ?? 0

        let remainingTotalSeconds = max(0, totalGoalSeconds - totalActualSeconds)
        let daysIncludingToday = max(1, daySnapshots.filter { $0.dayStart >= todayStart }.count)
        let daysAfterToday = daySnapshots.filter { $0.dayStart > todayStart }.count

        let completedBeforeTodaySeconds = daySnapshots
            .filter { $0.dayStart < todayStart }
            .reduce(0) { $0 + $1.totalSeconds }
        let remainingIncludingTodaySeconds = max(0, totalGoalSeconds - completedBeforeTodaySeconds)
        let perDayIncludingTodayHours = (remainingIncludingTodaySeconds / Double(max(1, daysIncludingToday))) / 3600
        let todayRecommendedHours = perDayIncludingTodayHours
        let todayActualHours = todaysActualSeconds / 3600
        let todayAdditionalHoursNeeded = max(0, todayRecommendedHours - todayActualHours)

        let remainingAfterTodaySeconds = max(0, totalGoalSeconds - (completedBeforeTodaySeconds + todaysActualSeconds))
        let futureDaysForPlan = max(0, daysAfterToday)
        let plannedFutureHours = futureDaysForPlan > 0 ? (remainingAfterTodaySeconds / Double(futureDaysForPlan)) / 3600 : 0
        let remainingDaysCount = remainingTotalSeconds > 0 ? futureDaysForPlan + (todayAdditionalHoursNeeded > 0 ? 1 : 0) : 0
        let recommendedDailyHours = remainingDaysCount > 0 ? (remainingTotalSeconds / 3600) / Double(remainingDaysCount) : 0

        var dayPlans: [WeeklyGoalProjection.DayPlan] = []
        for snapshot in daySnapshots {
            let actualHours = snapshot.totalSeconds / 3600
            let isFuture = snapshot.dayStart > todayStart
            let plannedHours: Double
            if snapshot.dayStart < todayStart {
                plannedHours = baselineDailyHours
            } else if calendar.isDate(snapshot.dayStart, inSameDayAs: todayStart) {
                plannedHours = max(actualHours, todayRecommendedHours)
            } else {
                plannedHours = plannedFutureHours
            }
            dayPlans.append(
                WeeklyGoalProjection.DayPlan(
                    dayStart: snapshot.dayStart,
                    actualHours: actualHours,
                    plannedHours: plannedHours,
                    isFuture: isFuture
                )
            )
        }

        let primeHourLabels: [String] = extendedSummary.hourlyMetrics
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(3)
            .map { hourRangeLabel(for: $0.hour) }

        return WeeklyGoalProjection(
            goalHours: weeklyGoalHours,
            actualHours: totalActualSeconds / 3600,
            completionFraction: completionFraction,
            remainingHours: remainingTotalSeconds / 3600,
            remainingDays: remainingDaysCount,
            recommendedDailyHours: recommendedDailyHours,
            todayActualHours: todayActualHours,
            todayRecommendedHours: todayRecommendedHours,
            todayAdditionalHoursNeeded: todayAdditionalHoursNeeded,
            primeHourLabels: primeHourLabels,
            dayPlans: dayPlans
        )
    }

    func weeklyProjectGoals(projects: [Project],
                            sessions: [FocusSession],
                            now: Date = .now,
                            capHours: Double = 112) -> WeeklyProjectGoalSummary {
        let weekStart = lookbackAnchor(for: now, days: 7)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now

        let goalProjects: [(project: Project, goalHours: Double)] = projects.compactMap { project in
            guard let goal = project.weeklyGoalHours, goal > 0 else { return nil }
            return (project, goal)
        }
        let goalProjectIDs = Set(goalProjects.map { $0.project.id })

        var actualSeconds: [UUID: TimeInterval] = [:]
        for session in sessions {
            guard let projectID = session.project?.id,
                  goalProjectIDs.contains(projectID) else { continue }
            let sessionEnd = session.endedAt ?? now
            if sessionEnd <= weekStart || session.startedAt >= weekEnd { continue }
            let clippedStart = max(session.startedAt, weekStart)
            let clippedEnd = min(sessionEnd, weekEnd)
            guard clippedEnd > clippedStart else { continue }
            actualSeconds[projectID, default: 0] += clippedEnd.timeIntervalSince(clippedStart)
        }

        var segments: [WeeklyProjectGoalSummary.Segment] = []
        for entry in goalProjects {
            let project = entry.project
            let goalHours = entry.goalHours
            let hours = (actualSeconds[project.id] ?? 0) / 3600
            let segment = WeeklyProjectGoalSummary.Segment(
                id: project.id,
                title: project.title,
                gradientIndex: project.gradientIndex,
                goalHours: goalHours,
                actualHours: hours
            )
            segments.append(segment)
        }

        let rawGoalHours = segments.reduce(0) { $0 + $1.goalHours }
        let scaleFactor = rawGoalHours > capHours && capHours > 0 ? capHours / rawGoalHours : 1
        let totalGoalHours = rawGoalHours * scaleFactor

        return WeeklyProjectGoalSummary(
            weekStart: weekStart,
            weekEnd: weekEnd,
            rawGoalHours: rawGoalHours,
            totalGoalHours: totalGoalHours,
            scaleFactor: scaleFactor,
            segments: segments
        )
    }

    func availableWeekOffsets(sessions: [FocusSession],
                              now: Date = .now,
                              config: TemporalInsightsConfig = TemporalInsightsConfig()) -> [Int] {
        let earliest = sessions.min(by: { $0.startedAt < $1.startedAt })?.startedAt
        guard let earliest else { return [0] }
        let earliestWeekStart = lookbackAnchor(for: earliest, days: config.lookbackDays)
        let currentWeekStart = lookbackAnchor(for: now, days: config.lookbackDays)
        let components = calendar.dateComponents([.weekOfYear], from: earliestWeekStart, to: currentWeekStart)
        let span = max(0, components.weekOfYear ?? 0)
        return Array(0...span)
    }
}

// MARK: - Helpers

private extension InsightsAnalyzer {
    func lookbackAnchor(for now: Date, days: Int) -> Date {
        guard days > 0 else { return Date.distantPast }
        if days == 7 {
            var weekCalendar = calendar
            weekCalendar.firstWeekday = 1 // Sunday
            weekCalendar.minimumDaysInFirstWeek = 1
            let dayStart = weekCalendar.startOfDay(for: now)
            if let interval = weekCalendar.dateInterval(of: .weekOfYear, for: dayStart) {
                return interval.start
            }
            let weekday = weekCalendar.component(.weekday, from: dayStart)
            let delta = weekday - weekCalendar.firstWeekday
            return weekCalendar.date(byAdding: .day, value: -delta, to: dayStart) ?? dayStart
        }
        let dayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -days + 1, to: dayStart) ?? dayStart
    }

    func accumulateHourlyMetrics(start: Date,
                                 end: Date,
                                 totals: inout [Int: TimeInterval],
                                 dailyHourTotals: inout [Date: [Int: TimeInterval]]) {
        var cursor = start
        while cursor < end {
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            guard let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { break }
            let segmentEnd = min(end, nextHour)
            let seconds = segmentEnd.timeIntervalSince(cursor)
            let hour = calendar.component(.hour, from: hourStart)
            totals[hour, default: 0] += seconds
            let dayStart = calendar.startOfDay(for: hourStart)
            var dayHours = dailyHourTotals[dayStart] ?? [:]
            dayHours[hour, default: 0] += seconds
            dailyHourTotals[dayStart] = dayHours
            cursor = segmentEnd
        }
    }

    func dailyStreakCount(from dayBuckets: Set<Date>) -> Int {
        guard let latestDay = dayBuckets.max() else { return 0 }
        var streak = 0
        var cursor = latestDay
        while dayBuckets.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func selectBestWindow(from metrics: [TemporalInsightsSummary.HourMetric], hours width: Int) -> TemporalInsightsSummary.BestFocusWindow? {
        guard width > 0 else { return nil }
        var best: TemporalInsightsSummary.BestFocusWindow?
        var bestScore: Double = 0

        let sorted = metrics.sorted { $0.hour < $1.hour }
        guard !sorted.isEmpty else { return nil }

        for startIndex in 0..<sorted.count {
            let windowItems = (0..<width).compactMap { offset -> TemporalInsightsSummary.HourMetric? in
                let idx = (startIndex + offset)
                return idx < sorted.count ? sorted[idx] : nil
            }
            guard windowItems.count == width else { break }

            let totalSeconds = windowItems.reduce(0) { $0 + $1.totalSeconds }
            guard totalSeconds > 0 else { continue }

            var windowMoodWeighted: Double = 0
            var windowMoodWeight: TimeInterval = 0
            for item in windowItems {
                if let avg = item.averageSatisfaction {
                    windowMoodWeighted += avg * item.totalSeconds
                    windowMoodWeight += item.totalSeconds
                }
            }
            let averageMood = windowMoodWeight > 0 ? windowMoodWeighted / windowMoodWeight : nil
            let moodFactor = averageMood.map { 1.0 + ($0 / 10.0) } ?? 1.0
            let score = totalSeconds * moodFactor
            if score > bestScore {
                bestScore = score
                let startHour = windowItems.first?.hour ?? 0
                let endHour = (windowItems.last?.hour ?? startHour) + 1
                best = TemporalInsightsSummary.BestFocusWindow(
                    startHour: startHour,
                    endHour: endHour,
                    totalSeconds: totalSeconds,
                    averageSatisfaction: averageMood
                )
            }
        }
        return best
    }

    func hourRangeLabel(for hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let start = calendar.date(from: components) ?? Date()
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        return "\(InsightsAnalyzer.hourFormatter.string(from: start)) - \(InsightsAnalyzer.hourFormatter.string(from: end))"
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? "h a"
        return formatter
    }()
}
