import Foundation

public struct DateUtils {
    public static let calendar = Calendar(identifier: .gregorian)

    public static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    // Split a session across day boundaries and return seconds per day start
    public static func splitByDay(start: Date, end: Date, calendar: Calendar = DateUtils.calendar) -> [(dayStart: Date, seconds: TimeInterval)] {
        precondition(end >= start, "end must be >= start")
        var parts: [(Date, TimeInterval)] = []
        var cursor = start
        while true {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let segmentEnd = min(end, nextDayStart)
            let seconds = segmentEnd.timeIntervalSince(cursor)
            parts.append((dayStart, max(0, seconds)))
            if segmentEnd >= end { break }
            cursor = nextDayStart
        }
        return parts
    }
}
