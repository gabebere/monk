import Foundation

enum AppGroupBridge {
    // Uses the shared App Group identifier; set in Monk/Shared/AppGroup.swift
    static let suiteName = AppGroup.id

    static func defaults() -> UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func writeSummary(todayHours: Double, last7: [Double]) {
        guard let d = defaults() else { return }
        let payload: [String: Any] = [
            "todayHours": todayHours,
            "last7": last7,
            "timestamp": Date().timeIntervalSince1970
        ]
        d.set(payload, forKey: "summary")
        d.synchronize()
    }
}
