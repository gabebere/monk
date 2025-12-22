import SwiftUI
import CoreLocation
import SwiftData
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif

public struct SetupChecklistView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var revenueCat: RevenueCatService
    @State private var calendars: [CalendarDisplayInfo] = []
    @State private var calendarStatus: String?
    @State private var calendarBusy = false
    @State private var showCalendarPicker = false
    @State private var notificationAuthorization: UNAuthorizationStatus?

    @Query private var prefsList: [Preferences]

    let onDone: () -> Void

    private var prefs: Preferences {
        if let existing = prefsList.first { return existing }
        let created = Preferences(hasConvertedDailyGoal: true)
        modelContext.insert(created)
        return created
    }

    public init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Set up Monk")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                checklist

                Spacer()

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .foregroundStyle(.white)
                }
            }
            .padding(24)
            .background(Theme.settingsBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await refreshNotificationStatus()
            }
            .confirmationDialog("Choose a calendar", isPresented: $showCalendarPicker, titleVisibility: .visible) {
                ForEach(calendars, id: \.id) { calendar in
                    Button(calendar.title) {
                        Task { await selectCalendar(calendar) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var checklist: some View {
        VStack(spacing: 14) {
            checklistRow(title: "Login", detail: "Sign in to sync your data and purchases.", status: auth.isAuthenticated ? .granted : .pending) {
                // Auth handled elsewhere
            }

            #if canImport(FamilyControls)
            checklistRow(title: "Screen Time access", detail: "Allow Monk to block distractions during focus sessions.", status: screenTimeStatus) {
                Task { await requestScreenTime() }
            }
            #endif

            checklistRow(title: "Calendar access", detail: "Write focus sessions to your calendar.", status: calendarStatusView) {
                Task { await prepareCalendarSelection() }
            }

            if let calendarStatus {
                Text(calendarStatus)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            checklistRow(title: "Location access", detail: "Add where you focused to calendar entries.", status: locationStatus) {
                Task { await requestLocation() }
            }

            checklistRow(title: "Notifications", detail: "Session reminders and wrap-up nudges.", status: notificationStatusView) {
                Task { await requestNotifications() }
            }
        }
    }

    private func checklistRow(title: String, detail: String, status: ChecklistStatus, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            status.icon
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button(action: action) {
                Text(status == .granted ? "Done" : "Enable")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(status == .granted)
            .opacity(status == .granted ? 0.6 : 1)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Status helpers

    #if canImport(FamilyControls)
    private var screenTimeStatus: ChecklistStatus {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: return .granted
        case .denied: return .denied
        default: return .pending
        }
    }
    #endif

    private var calendarStatusView: ChecklistStatus {
        if calendarBusy { return .pending }
        if prefs.calendarIntegrationEnabled == true, let id = prefs.calendarCalendarIdentifier, !id.isEmpty {
            return .granted
        }
        return .pending
    }

    private var locationStatus: ChecklistStatus {
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied, .restricted: return .denied
        default: return .pending
        }
    }

    private var notificationStatusView: ChecklistStatus {
        guard let status = notificationAuthorization else { return .pending }
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        default:
            return .pending
        }
    }

    // MARK: - Actions

    #if canImport(FamilyControls)
    private func requestScreenTime() async {
        _ = await HardBlockManager.shared.ensureAuthorization()
    }
    #endif

    private func refreshCalendars() async {
        calendarBusy = true
        let options = await CalendarIntegration.shared.availableCalendars()
        await MainActor.run {
            calendars = options
            calendarBusy = false
        }
    }

    private func prepareCalendarSelection() async {
        calendarBusy = true
        let granted = await CalendarIntegration.shared.requestAccess()
        guard granted else {
            await MainActor.run {
                calendarStatus = "Calendar access denied. Enable in Settings > Privacy > Calendars."
                calendarBusy = false
            }
            return
        }

        await refreshCalendars()
        await MainActor.run {
            calendarBusy = false
            if calendars.isEmpty {
                calendarStatus = "No writable calendars available. Check iOS Settings > Calendars."
            } else {
                showCalendarPicker = true
            }
        }
    }

    private func selectCalendar(_ calendar: CalendarDisplayInfo) async {
        await MainActor.run {
            prefs.calendarCalendarIdentifier = calendar.id
            prefs.calendarIntegrationEnabled = true
            modelContext.saveOrRollback()
            calendarStatus = "Calendar set to \(calendar.title)"
        }
    }

    private func requestLocation() async {
        _ = await LocationProvider.shared.requestLocation()
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationAuthorization = settings.authorizationStatus
        }
    }

    private func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                await MainActor.run {
                    notificationAuthorization = .denied
                }
            } else {
                await refreshNotificationStatus()
            }
        } catch {
            await MainActor.run {
                notificationAuthorization = .denied
            }
        }
    }
}

private enum ChecklistStatus {
    case pending
    case denied
    case granted

    @ViewBuilder
    var icon: some View {
        switch self {
        case .pending:
            Circle().stroke(Color.white.opacity(0.7), lineWidth: 2)
                .frame(width: 22, height: 22)
        case .denied:
            ZStack {
                Circle().fill(Color.red)
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
        case .granted:
            ZStack {
                Circle().fill(Color.green)
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
        }
    }
}
