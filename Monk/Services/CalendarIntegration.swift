import EventKit
import Foundation
import CoreLocation
import OSLog

struct CalendarDisplayInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceName: String
}

actor CalendarIntegration {
    static let shared = CalendarIntegration()

    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "CalendarIntegration")

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
            let matches = matchingEvents(for: session, calendar: calendar)
            if let keeper = matches.min(by: { duration(of: $0) < duration(of: $1) }) {
                let desiredDuration = min(duration(of: keeper), end.timeIntervalSince(session.startedAt))
                let newEnd = session.startedAt.addingTimeInterval(desiredDuration)
                keeper.title = session.calendarDisplayTitle
                keeper.startDate = session.startedAt
                keeper.endDate = newEnd
                keeper.notes = session.calendarSessionMarker
                applyLocation(session: session, to: keeper)
                try eventStore.save(keeper, span: .thisEvent)

                // Remove other duplicates
                let duplicates = matches.filter { $0.eventIdentifier != keeper.eventIdentifier }
                for duplicate in duplicates {
                    try? eventStore.remove(duplicate, span: .thisEvent, commit: false)
                }
                if !duplicates.isEmpty {
                    try? eventStore.commit()
                }
                return
            }

            let event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
            event.title = session.calendarDisplayTitle
            event.startDate = session.startedAt
            event.endDate = end
            event.notes = session.calendarSessionMarker
            applyLocation(session: session, to: event)
            try eventStore.save(event, span: .thisEvent)
        } catch {
            logger.error("Failed to log focus session to calendar: \(error.localizedDescription, privacy: .public)")
        }
    }

    func updateEventLocation(for session: FocusSession, calendarIdentifier: String) async {
        guard session.endedAt != nil else { return }
        guard await requestAccessIfNeeded(),
              let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else {
            return
        }

        let events = matchingEvents(for: session, calendar: calendar)
        guard let event = events.first else { return }

        applyLocation(session: session, to: event)

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            logger.error("Failed to update calendar event location: \(error.localizedDescription, privacy: .public)")
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

    func upsertHealthEvent(existingIdentifier: String?,
                           calendarIdentifier: String,
                           title: String,
                           start: Date,
                           end: Date,
                           notes: String?) async -> String? {
        guard await requestAccessIfNeeded() else { return nil }
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else { return nil }

        let event: EKEvent
        if let existingIdentifier,
           let existing = eventStore.event(withIdentifier: existingIdentifier) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
        }

        event.title = title
        event.startDate = start
        if end > start {
            event.endDate = end
        } else {
            event.endDate = start.addingTimeInterval(60)
        }
        event.notes = notes
        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            logger.error("Failed to upsert health event: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func deleteEvent(identifier: String) async {
        guard await requestAccessIfNeeded() else { return }
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        try? eventStore.remove(event, span: .thisEvent, commit: true)
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

    private func matchingEvents(for session: FocusSession, calendar: EKCalendar) -> [EKEvent] {
        guard let end = session.endedAt else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: session.startedAt.addingTimeInterval(-120),
                                                      end: end.addingTimeInterval(120),
                                                      calendars: [calendar])
        let marker = session.calendarSessionMarker.lowercased()
        return eventStore.events(matching: predicate).filter { event in
            if let notes = event.notes?.lowercased(), notes.contains(marker) { return true }
            return eventMatchesSession(event, session: session)
        }
    }

    private func duration(of event: EKEvent) -> TimeInterval {
        max(0, event.endDate.timeIntervalSince(event.startDate))
    }

    private func applyLocation(session: FocusSession, to event: EKEvent) {
        if let locationName = session.locationName {
            event.location = locationName
        }
        if let lat = session.locationLatitude, let lon = session.locationLongitude {
            let structured = EKStructuredLocation(title: session.locationName ?? "Focus Session")
            structured.geoLocation = CLLocation(latitude: lat, longitude: lon)
            event.structuredLocation = structured
        }
    }

    private func isMonkEvent(_ event: EKEvent) -> Bool {
        if let notes = event.notes?.lowercased(),
           notes.contains("monksession:") {
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

    private func eventMatchesSession(_ event: EKEvent, session: FocusSession) -> Bool {
        let marker = session.calendarSessionMarker.lowercased()
        if let notes = event.notes?.lowercased(), notes.contains(marker) { return true }
        if let title = event.title?.lowercased(),
           title == session.calendarDisplayTitle.lowercased() {
            return true
        }
        return isMonkEvent(event)
    }

    private func logMonkDiagnostics(context: String, targetCalendar: EKCalendar? = nil, calendars: [EKCalendar]? = nil) async {
        // Diagnostics removed
    }

    private func monkEvents(in calendars: [EKCalendar], window: (start: Date, end: Date)) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
        return  eventStore.events(matching: predicate).filter(isMonkEvent)
    }
}
