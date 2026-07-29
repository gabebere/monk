import Foundation

struct FocusDurationComponents {
    static func sanitizedHours(_ value: String) -> String {
        sanitized(value, maximum: 99)
    }

    static func sanitizedMinutes(_ value: String) -> String {
        sanitized(value, maximum: 59)
    }

    static func totalMinutes(hours: String, minutes: String) -> Int {
        (Int(hours) ?? 0) * 60 + (Int(minutes) ?? 0)
    }

    private static func sanitized(_ value: String, maximum: Int) -> String {
        let digits = String(value.filter(\.isNumber).prefix(2))
        guard let number = Int(digits) else { return "" }
        return String(min(number, maximum))
    }
}
