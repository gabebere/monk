import EventKit
import Foundation
import CoreLocation

struct CalendarDisplayInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceName: String
}

actor CalendarIntegration {
    static let shared = CalendarIntegration()

    private let eventStore = EKEventStore()

    func requestAccess() async -> Bool {
        return await requestAccessIfNeeded()
    }

    func availableCalendars() async -> [CalendarDisplayInfo] {
        guard await requestAccessIfNeeded() else { return [] }
        return eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { cal in
                CalendarDisplayInfo(id: cal.calendarIdentifier,
                                    title: cal.title,
                                    sourceName: cal.source.title)
            }
            .sorted { $0.title < $1.title }
    }

    func logSession(_ session: FocusSession, calendarIdentifier: String) async {
        guard let end = session.endedAt else { return }
        guard await requestAccessIfNeeded(),
              let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else {
            print("[CalendarIntegration] Calendar unavailable or access denied for \(calendarIdentifier)")
            return
        }

        do {
            if try await hasEvent(for: session, in: calendar) { return }
            let event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
            event.title = "[Monk] \(session.project?.title ?? "Focus Session")"
            event.startDate = session.startedAt
            event.endDate = end
            // Avoid leaving internal markers in user-visible notes
            if let location = session.locationName {
                event.location = location
                print("[CalendarIntegration] Attaching location name to event: \(location)")
            }
            if let lat = session.locationLatitude, let lon = session.locationLongitude {
                let structured = EKStructuredLocation(title: session.locationName ?? "Focus Session")
                structured.geoLocation = CLLocation(latitude: lat, longitude: lon)
                event.structuredLocation = structured
                print("[CalendarIntegration] Attaching coordinates \(lat), \(lon)")
            } else {
                print("[CalendarIntegration] No coordinates available for session \(session.id)")
            }
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("CalendarIntegration log error: \(error.localizedDescription)")
        }
    }

    func backfillSessions(_ sessions: [FocusSession], calendarIdentifier: String) async {
        guard await requestAccessIfNeeded(),
              eventStore.calendar(withIdentifier: calendarIdentifier) != nil else { return }
        for session in sessions where session.endedAt != nil {
            await logSession(session, calendarIdentifier: calendarIdentifier)
        }
    }

    func purgeMonkEvents(in calendarIdentifier: String) async -> Int {
        guard await requestAccessIfNeeded(),
              let calendar = eventStore.calendar(withIdentifier: calendarIdentifier),
              calendar.allowsContentModifications else { return 0 }
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 5)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let events = eventStore.events(matching: predicate).filter(isMonkEvent)
        var removed = 0
        for event in events {
            do {
                try eventStore.remove(event, span: .thisEvent)
                removed += 1
            } catch {
                print("Failed to remove event \(event.eventIdentifier ?? "nil"): \(error.localizedDescription)")
            }
        }
        return removed
    }

    func purgeAllMonkEvents() async -> Int {
        guard await requestAccessIfNeeded() else { return 0 }
        let allCalendars = eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 5)
        var totalRemoved = 0
        for calendar in allCalendars {
            let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [calendar])
            let events = eventStore.events(matching: predicate).filter(isMonkEvent)
            for event in events {
                do {
                    try eventStore.remove(event, span: .thisEvent)
                    totalRemoved += 1
                } catch {
                    print("Failed to purge event \(event.eventIdentifier ?? "nil") from \(calendar.title): \(error.localizedDescription)")
                }
            }
        }
        return totalRemoved
    }

    private func requestAccessIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess, .authorized:
                return true
            case .writeOnly:
                return true
            case .denied, .restricted:
                return false
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    eventStore.requestFullAccessToEvents { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized:
                return true
            case .fullAccess:
                return true
            case .writeOnly:
                return true
            case .denied, .restricted:
                return false
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }
    }

    private func hasEvent(for session: FocusSession, in calendar: EKCalendar) async throws -> Bool {
        guard let end = session.endedAt else { return false }
        let predicate = eventStore.predicateForEvents(withStart: session.startedAt.addingTimeInterval(-60),
                                                      end: end.addingTimeInterval(60),
                                                      calendars: [calendar])
        let events = eventStore.events(matching: predicate)
        return events.contains { $0.notes == eventMarker(for: session) }
    }

    private func eventMarker(for session: FocusSession) -> String {
        "MonkSession:\(session.id.uuidString)"
    }

    private func isMonkEvent(_ event: EKEvent) -> Bool {
        if let notes = event.notes,
           notes.range(of: "MonkSession:", options: [.caseInsensitive]) != nil {
            return true
        }
        if let title = event.title?.lowercased() {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[monk]") { return true }
            if trimmed.contains("[monk") { return true }
        }
        return false
    }
}
