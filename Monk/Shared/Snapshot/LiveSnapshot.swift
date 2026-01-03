import Foundation

enum TimerSnapshotState: String, Codable {
    case idle
    case running
    case paused
    case stopped
}

struct LiveSnapshot: Codable {
    var sessionID: UUID?
    var taskTitle: String?
    var projectTitle: String?
    var timerState: TimerSnapshotState
    var timerStart: Date?
    var timerEnd: Date?
    var elapsedSeconds: TimeInterval
    var weeklyGoalSeconds: TimeInterval?
    var weeklyCompletedSeconds: TimeInterval?
    var weeklyRemainingSeconds: TimeInterval?
    var todayGoalSeconds: TimeInterval?
    var todayCompletedSeconds: TimeInterval?
    var todayRemainingSeconds: TimeInterval?
    var projectGoals: WeeklyGoalsSnapshot?
    var lastUpdatedAt: Date

    static var empty: LiveSnapshot {
        LiveSnapshot(
            sessionID: nil,
            taskTitle: nil,
            projectTitle: nil,
            timerState: .idle,
            timerStart: nil,
            timerEnd: nil,
            elapsedSeconds: 0,
            weeklyGoalSeconds: nil,
            weeklyCompletedSeconds: nil,
            weeklyRemainingSeconds: nil,
            todayGoalSeconds: nil,
            todayCompletedSeconds: nil,
            todayRemainingSeconds: nil,
            projectGoals: nil,
            lastUpdatedAt: Date()
        )
    }

    var isActive: Bool {
        timerState == .running || timerState == .paused
    }
}

struct WeeklyGoalsSnapshot: Codable {
    struct Segment: Codable, Identifiable {
        var id: UUID
        var title: String
        var gradientIndex: Int
        var goalHours: Double
        var actualHours: Double
    }

    var weekStart: Date
    var weekEnd: Date
    var rawGoalHours: Double
    var totalGoalHours: Double
    var scaleFactor: Double
    var segments: [Segment]

    var hasGoals: Bool {
        totalGoalHours > 0 && !segments.isEmpty
    }

    var totalActualHours: Double {
        segments.reduce(0) { $0 + $1.actualHours }
    }
}

enum SnapshotStorage {
    static let appGroupIdentifier = "group.com.gbr.Monk"
    static let snapshotFileName = "live_snapshot.json"
    static let userDefaultsKey = "live_snapshot_payload"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
