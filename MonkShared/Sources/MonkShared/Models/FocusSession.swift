import Foundation
import SwiftData

@Model
public final class FocusSession {
    public var id: UUID = Foundation.UUID()
    public var startedAt: Date = Foundation.Date()
    public var endedAt: Date?
    public var project: Project?
    public var locationName: String?
    public var locationLatitude: Double?
    public var locationLongitude: Double?

    public init(id: UUID = UUID(),
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

public extension FocusSession {
    var isInProgress: Bool { endedAt == nil }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}
