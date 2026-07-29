import Foundation

enum MobileFocusInput {
    static func sanitizedHours(_ value: String) -> String {
        sanitizedNumber(value, maximum: 99)
    }

    static func sanitizedMinutes(_ value: String) -> String {
        sanitizedNumber(value, maximum: 59)
    }

    static func totalMinutes(hours: String, minutes: String) -> Int {
        (Int(hours) ?? 0) * 60 + (Int(minutes) ?? 0)
    }

    static func normalizedDomain(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return nil }

        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard let components = URLComponents(string: candidate),
              var host = components.host?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              host.contains("."), !host.contains(" ") else {
            return nil
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host.isEmpty ? nil : host
    }

    private static func sanitizedNumber(_ value: String, maximum: Int) -> String {
        let digits = String(value.filter(\.isNumber).prefix(2))
        guard let number = Int(digits) else { return "" }
        return String(min(number, maximum))
    }
}
