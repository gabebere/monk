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
                activeDayCount: 0
            )
        }

        var totalSeconds: TimeInterval = 0
        var sampleCount = 0
        var satisfactionWeightedSum: Double = 0
        var satisfactionWeight: TimeInterval = 0

        var hourlyTotals: [Int: TimeInterval] = [:]
        var hourlyMoodSums: [Int: Double] = [:]
        var hourlyMoodWeights: [Int: TimeInterval] = [:]

        var dailyTotals: [Date: TimeInterval] = [:]
        var dailyMoodSums: [Date: Double] = [:]
        var dailyMoodWeights: [Date: TimeInterval] = [:]
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

            if let mood = session.moodScore {
                let score = satisfactionScore(for: mood)
                satisfactionWeightedSum += score * duration
                satisfactionWeight += duration
            }

            accumulateHourlyMetrics(
                start: clippedStart,
                end: clippedEnd,
                moodScore: session.moodScore,
                totals: &hourlyTotals,
                moodSums: &hourlyMoodSums,
                moodWeights: &hourlyMoodWeights
            )

            for part in DateUtils.splitByDay(start: clippedStart, end: clippedEnd, calendar: calendar) {
                guard part.seconds > 0 else { continue }
                dailyTotals[part.dayStart, default: 0] += part.seconds
                if let mood = session.moodScore {
                    let score = satisfactionScore(for: mood)
                    dailyMoodSums[part.dayStart, default: 0] += score * part.seconds
                    dailyMoodWeights[part.dayStart, default: 0] += part.seconds
                }
                dailySessionIds[part.dayStart, default: []].insert(session.id)
            }
        }

        let averageSatisfaction = satisfactionWeight > 0 ? satisfactionWeightedSum / satisfactionWeight : nil
        let hourlyMetrics = (0..<24).map { hour -> TemporalInsightsSummary.HourMetric in
            let total = hourlyTotals[hour] ?? 0
            let moodSum = hourlyMoodSums[hour] ?? 0
            let moodWeight = hourlyMoodWeights[hour] ?? 0
            let average = moodWeight > 0 ? moodSum / moodWeight : nil
            return TemporalInsightsSummary.HourMetric(hour: hour, totalSeconds: total, averageSatisfaction: average)
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
            let moodWeight = dailyMoodWeights[dayStart] ?? 0
            let moodSum = dailyMoodSums[dayStart] ?? 0
            let moodAverage = moodWeight > 0 ? moodSum / moodWeight : nil
            let sessionCount = dailySessionIds[dayStart]?.count ?? 0
            return TemporalInsightsSummary.DaySnapshot(
                dayStart: dayStart,
                totalSeconds: total,
                averageSatisfaction: moodAverage,
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
            averageSatisfaction: averageSatisfaction,
            dailyStreakCount: streak,
            hourlyMetrics: hourlyMetrics,
            topHourMetrics: Array(topHourMetrics),
            bestWindow: bestWindow,
            dailySnapshots: dailySnapshots,
            activeDayCount: activeDayCount
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

    func satisfactionScore(for mood: Int) -> Double {
        let clamped = max(0, min(2, mood))
        return (Double(clamped) / 2.0) * 10.0
    }

    func accumulateHourlyMetrics(start: Date,
                                 end: Date,
                                 moodScore: Int?,
                                 totals: inout [Int: TimeInterval],
                                 moodSums: inout [Int: Double],
                                 moodWeights: inout [Int: TimeInterval]) {
        var cursor = start
        while cursor < end {
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            guard let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { break }
            let segmentEnd = min(end, nextHour)
            let seconds = segmentEnd.timeIntervalSince(cursor)
            let hour = calendar.component(.hour, from: hourStart)
            totals[hour, default: 0] += seconds
            if let mood = moodScore {
                let score = satisfactionScore(for: mood)
                moodSums[hour, default: 0] += score * seconds
                moodWeights[hour, default: 0] += seconds
            }
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
}
