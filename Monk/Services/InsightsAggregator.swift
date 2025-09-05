import Foundation

enum InsightsAggregator {
    /// Computes total hours for the last `n` days ending at the exclusive upper bound `end` (start-of-tomorrow for `now`).
    /// - Returns: An array of length `n`, oldest to newest, in hours.
    static func lastNDaysTotals(sessions: [FocusSession], n: Int, now: Date, calendar: Calendar) -> [Double] {
        guard n > 0 else { return [] }
        let end = calendar.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        guard let start = calendar.date(byAdding: .day, value: -n, to: end) else { return [] }

        var buckets: [Date: TimeInterval] = [:]
        for s in sessions {
            let sStart = max(s.startedAt, start)
            let sEnd = min(s.endedAt ?? now, end)
            guard sEnd > sStart else { continue }
            for part in DateUtils.splitByDay(start: sStart, end: sEnd, calendar: calendar) {
                buckets[part.dayStart, default: 0] += part.seconds
            }
        }

        var result: [Double] = []
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let hours = (buckets[dayStart] ?? 0) / 3600
            result.append(hours)
            cursor = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        }
        return result
    }
}

