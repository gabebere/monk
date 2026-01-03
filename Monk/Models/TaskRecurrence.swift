import Foundation

enum TaskRecurrence: String, Codable, CaseIterable, Equatable {
    case none
    case daily
    case weekly
    case monthly
    case custom
}

extension TaskRecurrence {
    var displayName: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .custom: return "Custom"
        }
    }

    func formattedLabel(intervalDays: Int?) -> String {
        switch self {
        case .none:
            return "None"
        case .daily, .weekly, .monthly:
            return displayName
        case .custom:
            if let interval = intervalDays, interval >= 1 {
                return "Every \(interval) day\(interval == 1 ? "" : "s")"
            }
            return "Custom"
        }
    }
}
