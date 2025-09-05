import Foundation
import SwiftData

enum CSVExporter {
    enum RangeOption: Equatable {
        case all
        case lastDays(Int)
        case since(Date)
    }

    static func makeCSV(from sessions: [FocusSession]) -> String {
        var rows: [String] = ["id,started_at_iso8601,ended_at_iso8601,duration_s,tags,feelings"]
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        for s in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let id = s.id.uuidString
            let started = fmt.string(from: s.startedAt)
            let ended = s.endedAt != nil ? fmt.string(from: s.endedAt!) : ""
            let duration = String(Int(max(0, (s.endedAt ?? Date()).timeIntervalSince(s.startedAt))))
            let tags = s.tags.joined(separator: ";")
            let feelings = s.feelings.joined(separator: ";")
            rows.append([id, started, ended, duration, tags, feelings].map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func writeTemporaryCSV(_ csv: String, filename: String = defaultFilename()) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    static func defaultFilename(now: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        return "DeepWork-\(df.string(from: now)).csv"
    }

    private static func csvEscape(_ field: String) -> String {
        var needsQuotes = false
        var value = field
        if value.contains("\"") {
            value = value.replacingOccurrences(of: "\"", with: "\"\"")
            needsQuotes = true
        }
        if value.contains(",") || value.contains("\n") || value.contains("\r") {
            needsQuotes = true
        }
        return needsQuotes ? "\"\(value)\"" : value
    }
}
