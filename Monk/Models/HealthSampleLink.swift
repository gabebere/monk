import Foundation
import SwiftData

enum HealthSampleKind: String, Codable {
    case workout
    case sleepInBed
    case sleepAsleep
}

@Model
final class HealthSampleLink {
    var sampleId: String?
    var kindRaw: String?
    var eventIdentifier: String?
    var startDate: Date?
    var endDate: Date?
    var lastImportedAt: Date?
    var projectId: UUID?

    init(sampleId: String,
         kind: HealthSampleKind,
         eventIdentifier: String? = nil,
         startDate: Date,
         endDate: Date,
         lastImportedAt: Date = .now,
         projectId: UUID? = nil) {
        self.sampleId = sampleId
        self.kindRaw = kind.rawValue
        self.eventIdentifier = eventIdentifier
        self.startDate = startDate
        self.endDate = endDate
        self.lastImportedAt = lastImportedAt
        self.projectId = projectId
    }

    var kind: HealthSampleKind {
        get { HealthSampleKind(rawValue: kindRaw ?? "") ?? .workout }
        set { kindRaw = newValue.rawValue }
    }
}
