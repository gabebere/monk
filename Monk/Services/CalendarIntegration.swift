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

    /// Shared cleanup window (±1 year)
    private func cleanupWindow() -> (start: Date, end: Date) {
        let now = Date()
        let start = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 3600)
        let end = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now.addingTimeInterval(365 * 24 * 3600)
        return (start, end)
    }

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
            }
            if let lat = session.locationLatitude, let lon = session.locationLongitude {
                let structured = EKStructuredLocation(title: session.locationName ?? "Focus Session")
                structured.geoLocation = CLLocation(latitude: lat, longitude: lon)
                event.structuredLocation = structured
            }
            try eventStore.save(event, span: .thisEvent)
        } catch {
        }
    }

    func updateEventLocation(for session: FocusSession, calendarIdentifier: String) async {
        guard let end = session.endedAt else { return }
        guard await requestAccessIfNeeded(),
              let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else {
            return
        }

        let predicate = eventStore.predicateForEvents(withStart: session.startedAt.addingTimeInterval(-60),
                                                      end: end.addingTimeInterval(60),
                                                      calendars: [calendar])
        let events = eventStore.events(matching: predicate).filter(isMonkEvent)
        guard let event = events.first else { return }

        if let locationName = session.locationName {
            event.location = locationName
        }
        if let lat = session.locationLatitude, let lon = session.locationLongitude {
            let structured = EKStructuredLocation(title: session.locationName ?? "Focus Session")
            structured.geoLocation = CLLocation(latitude: lat, longitude: lon)
            event.structuredLocation = structured
        }

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
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
        guard await requestAccessIfNeeded() else { return 0 }
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else { return 0 }

        let window = cleanupWindow()
        let events = monkEvents(in: [calendar], window: window)

        var removed = 0
        for event in events {
            guard calendar.allowsContentModifications else {
                continue
            }
            try? eventStore.remove(event, span: .thisEvent, commit: false)
            removed += 1
        }
        if removed > 0 {
            try? eventStore.commit()
        }

        // Extra sweep across all calendars in case events landed elsewhere
        removed += await purgeAllMonkEvents()
        return removed
    }

    func purgeAllMonkEvents() async -> Int {
        guard await requestAccessIfNeeded() else { return 0 }
        let allCalendars = eventStore.calendars(for: .event)
        await logMonkDiagnostics(context: "purgeAllMonkEvents", calendars: allCalendars)
        let window = cleanupWindow()
        var totalRemoved = 0

        let events = monkEvents(in: allCalendars, window: window)
        for event in events {
            guard event.calendar.allowsContentModifications else {
                continue
            }
            try? eventStore.remove(event, span: .thisEvent, commit: false)
            totalRemoved += 1
        }
        if totalRemoved > 0 {
            try? eventStore.commit()
        }
        return totalRemoved
    }

    private func requestAccessIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess, .authorized:
                return true
            case .writeOnly:
                return false // write-only cannot read/delete
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
            case .authorized, .fullAccess:
                return true
            case .writeOnly:
                return false
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
        let tolerance: TimeInterval = 120
        let expectedTitle = "[monk] \(session.project?.title ?? "focus session")".lowercased()
        return events.contains { event in
            guard isMonkEvent(event) else { return false }
            let startDiff = abs(event.startDate.timeIntervalSince(session.startedAt))
            let endDiff = abs(event.endDate.timeIntervalSince(end))
            if startDiff > tolerance || endDiff > tolerance { return false }
            if let title = event.title?.lowercased(), title == expectedTitle {
                return true
            }
            return true
        }
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
            if trimmed.contains("monk") { return true }
        }
        return false
    }

    private func logMonkDiagnostics(context: String, targetCalendar: EKCalendar? = nil, calendars: [EKCalendar]? = nil) async {
        // Diagnostics removed
    }

    private func monkEvents(in calendars: [EKCalendar], window: (start: Date, end: Date)) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
        return  eventStore.events(matching: predicate).filter(isMonkEvent)
    }
}
