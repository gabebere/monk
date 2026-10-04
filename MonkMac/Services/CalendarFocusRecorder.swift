import AppKit
import Combine
import EventKit
import Foundation
import OSLog

@MainActor
protocol FocusCalendarRecording: AnyObject {
    func recordCompletedFocus(_ policy: FocusPolicy)
}

@MainActor
final class CalendarFocusRecorder: ObservableObject, FocusCalendarRecording {
    static let enabledDefaultsKey = "com.gbr.Monk.calendarRecordingEnabled"
    private static let recordedSessionIDsKey = "com.gbr.Monk.calendarRecordedSessionIDs"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var lastErrorMessage: String?

    private let eventStore: EKEventStore
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.gbr.Monk.mac", category: "Calendar")

    init(eventStore: EKEventStore = EKEventStore(), defaults: UserDefaults = .standard) {
        self.eventStore = eventStore
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var statusMessage: String {
        if let lastErrorMessage {
            return lastErrorMessage
        }

        switch authorizationStatus {
        case .fullAccess:
            return isEnabled
                ? "Completed focuses are added to your default calendar."
                : "Calendar recording is off."
        case .denied, .restricted:
            return "Calendar access is disabled in System Settings."
        case .notDetermined, .writeOnly:
            return "MonkOS will ask for calendar access when you enable this."
        @unknown default:
            return "Calendar access is unavailable."
        }
    }

    var canOpenPrivacySettings: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func setEnabled(_ enabled: Bool) async {
        lastErrorMessage = nil
        guard enabled else {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledDefaultsKey)
            return
        }

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            isEnabled = granted
            defaults.set(granted, forKey: Self.enabledDefaultsKey)
            if !granted {
                lastErrorMessage = "Calendar access was not granted."
            }
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            isEnabled = false
            defaults.set(false, forKey: Self.enabledDefaultsKey)
            lastErrorMessage = "MonkOS could not access Calendar: \(error.localizedDescription)"
            logger.error("Calendar authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordCompletedFocus(_ policy: FocusPolicy) {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard isEnabled, authorizationStatus == .fullAccess else { return }

        var recordedSessionIDs = Set(
            defaults.stringArray(forKey: Self.recordedSessionIDsKey) ?? []
        )
        guard recordedSessionIDs.insert(policy.id.uuidString).inserted else { return }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            lastErrorMessage = "Choose a default calendar in Calendar settings first."
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = policy.intention
        event.notes = "Focused with MonkOS"
        event.startDate = policy.startedAt
        event.endDate = max(policy.endsAt, policy.startedAt.addingTimeInterval(60))

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            defaults.set(Array(recordedSessionIDs.suffix(500)), forKey: Self.recordedSessionIDsKey)
            logger.notice("Recorded completed focus \(policy.id.uuidString, privacy: .public) in Calendar")
        } catch {
            lastErrorMessage = "MonkOS could not add the completed focus to Calendar."
            logger.error("Calendar event save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func openPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
