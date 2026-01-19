// Calendar selection sync was removed; file retained to avoid breaking imports.
// In case any legacy references linger, this no-op stub preserves API surface.
import Foundation
import Combine

@MainActor
final class CalendarSelectionSyncService: ObservableObject {
    static let shared = CalendarSelectionSyncService()

    @Published private(set) var selectedCalendarId: String?
    @Published private(set) var lastUpdated: Date?

    private init() {}

    func updateSelected(id: String?) {
        selectedCalendarId = id
        lastUpdated = Date()
    }
}
