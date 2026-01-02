import Foundation
import SwiftData

@Model
final class FocusSession {
    var id: UUID = Foundation.UUID()
    var startedAt: Date = Foundation.Date()
    var endedAt: Date?
    var project: Project?
    var locationName: String?
    var locationLatitude: Double?
    var locationLongitude: Double?

    init(id: UUID = UUID(),
         startedAt: Date = .now,
         endedAt: Date? = nil,
         project: Project? = nil,
         locationName: String? = nil,
         locationLatitude: Double? = nil,
         locationLongitude: Double? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.project = project
        self.locationName = locationName
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
    }
}

extension FocusSession {
    var isInProgress: Bool { endedAt == nil }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}
