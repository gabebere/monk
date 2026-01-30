import Foundation
import OSLog
import ManagedSettings
import FamilyControls

struct IntentSchedule: Codable, Equatable {
    /// 1 = Sunday ... 7 = Saturday (Calendar.component(.weekday))
    var daysOfWeek: Set<Int>
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute,
              daysOfWeek.contains(weekday) else { return false }

        let minutesSinceMidnight = hour * 60 + minute
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute

        if start == end { return true } // treat as always-on during selected days
        if start < end {
            return minutesSinceMidnight >= start && minutesSinceMidnight < end
        } else {
            // Overnight window (e.g., 22:00 -> 06:00)
            return minutesSinceMidnight >= start || minutesSinceMidnight < end
        }
    }

    func nextInterval(from date: Date, calendar: Calendar = .current) -> DateInterval? {
        // Compute the next active interval start/end after the provided date.
        // Handles overnight windows by splitting across days when needed.
        var searchDate = calendar.startOfDay(for: date)
        for _ in 0..<14 { // look ahead up to 2 weeks to stay safe
            let weekday = calendar.component(.weekday, from: searchDate)
            if daysOfWeek.contains(weekday) {
                guard let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: searchDate),
                      let endBase = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: searchDate) else {
                    continue
                }

                let end = endHour * 60 + endMinute >= startHour * 60 + startMinute
                ? endBase
                : calendar.date(byAdding: .day, value: 1, to: endBase)

                if let end = end {
                    if end > date { // upcoming interval
                        let interval = DateInterval(start: start, end: end)
                        if interval.end > date { return interval }
                    }
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: searchDate) else { break }
            searchDate = nextDay
        }
        return nil
    }
}

struct IntentUnlock: Codable {
    let applicationTokenData: Data
    let startedAt: Date
    let durationSeconds: Int

    var expiresAt: Date {
        startedAt.addingTimeInterval(TimeInterval(durationSeconds))
    }

    var token: ManagedSettings.ApplicationToken? {
        try? JSONDecoder().decode(ManagedSettings.ApplicationToken.self, from: applicationTokenData)
    }
}

struct IntentState: Codable {
    var baselineEnabled: Bool
    var baselineScheduleEnabled: Bool
    var baselineScheduleData: Data?
    var baselineAlwaysAllowedSelectionData: Data?
    var baselineNeverBlockCategoriesSelectionData: Data?
    var baselineUnlockableAppsSelectionData: Data?
    var activeUnlocks: [IntentUnlock]
    var updatedAt: Date
}

enum IntentStateStore {
    private static let suiteName = "group.com.gbr.Monk"
    private static let fileName = "intentState.json"
    private static let logger = Logger(subsystem: "com.gbr.Monk", category: "IntentStateStore")
    private static var didBootstrap = false

    static func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        let fm = FileManager.default
        if let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            if !fm.fileExists(atPath: containerURL.path) {
                do {
                    try fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
                } catch {
                    logger.error("Failed to create directory for intent state: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            logger.error("Unable to resolve app group container for intent state store.")
        }
    }

    static func load() -> IntentState? {
        guard let url = stateURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IntentState.self, from: data)
    }

    static func save(_ state: IntentState) {
        guard let url = stateURL() else { return }
        do {
            let encoded = try JSONEncoder().encode(state)
            try encoded.write(to: url, options: [.atomic])
        } catch {
            logger.error("Failed to write intent state: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func replaceActiveUnlocks(_ unlocks: [IntentUnlock]) {
        var state = load() ?? defaultState()
        state.activeUnlocks = unlocks
        state.updatedAt = Date()
        save(state)
    }

    static func syncFromPreferences(_ preferences: Preferences, activeUnlocks: [IntentUnlock]? = nil) {
        var state = load() ?? defaultState()
        state.baselineEnabled = preferences.baselineEnabled
        state.baselineScheduleEnabled = preferences.baselineScheduleEnabled
        state.baselineScheduleData = preferences.baselineScheduleData
        state.baselineAlwaysAllowedSelectionData = preferences.baselineAlwaysAllowedSelectionData
        state.baselineNeverBlockCategoriesSelectionData = preferences.baselineNeverBlockCategoriesSelectionData
        state.baselineUnlockableAppsSelectionData = preferences.baselineUnlockableAppsSelectionData
        if let activeUnlocks { state.activeUnlocks = activeUnlocks }
        state.updatedAt = Date()
        save(state)
    }

    static func defaultState() -> IntentState {
        IntentState(
            baselineEnabled: false,
            baselineScheduleEnabled: false,
            baselineScheduleData: nil,
            baselineAlwaysAllowedSelectionData: nil,
            baselineNeverBlockCategoriesSelectionData: nil,
            baselineUnlockableAppsSelectionData: nil,
            activeUnlocks: [],
            updatedAt: Date()
        )
    }

    private static func stateURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else {
            logger.error("Cannot resolve intent state URL because the container is unavailable")
            return nil
        }
        return containerURL.appendingPathComponent(fileName, isDirectory: false)
    }
}
