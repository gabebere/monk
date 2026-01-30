import Foundation
import SwiftData

enum UnlockSource: String, Codable {
    case shortcut
    case siri
    case inAppFallback
}

@Model
final class UnlockEvent {
    var id: UUID = UUID()
    var applicationTokenData: Data = Data()
    var appDisplayName: String = ""
    var startedAt: Date = Date()
    var durationSeconds: Int = 0
    var sourceRaw: String = UnlockSource.shortcut.rawValue

    init(id: UUID = UUID(),
         applicationTokenData: Data,
         appDisplayName: String,
         startedAt: Date = Date(),
         durationSeconds: Int,
         source: UnlockSource) {
        self.id = id
        self.applicationTokenData = applicationTokenData
        self.appDisplayName = appDisplayName
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.sourceRaw = source.rawValue
    }
}

extension UnlockEvent {
    var source: UnlockSource {
        get { UnlockSource(rawValue: sourceRaw) ?? .shortcut }
        set { sourceRaw = newValue.rawValue }
    }

    var expiresAt: Date {
        startedAt.addingTimeInterval(TimeInterval(durationSeconds))
    }
}
