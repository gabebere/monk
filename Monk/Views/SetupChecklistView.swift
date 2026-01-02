import SwiftUI
import FamilyControls
import CoreLocation
import SwiftData

struct SetupChecklistView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var revenueCat: RevenueCatService
    @State private var calendars: [CalendarDisplayInfo] = []
    @State private var calendarStatus: String?
    @State private var calendarBusy = false
    @State private var screenTimeBusy = false
    @State private var locationBusy = false
    @State private var showCalendarPicker = false
    @State private var selectedCalendarId: String?
    @State private var selectedCalendarName: String?
    @State private var didPrefetchCalendars = false

    @Query private var prefsList: [Preferences]

    let onDone: () -> Void

    private var prefs: Preferences {
        if let existing = prefsList.first { return existing }
        let created = Preferences(hasConvertedDailyGoal: true)
        modelContext.insert(created)
        return created
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatingBackground()
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Getting started")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    checklist

                    Spacer()

                    Button {
                        onDone()
                    } label: {
                        Text("Next")
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCalendarPicker) {
                NavigationStack {
                    VStack(spacing: 16) {
                        Text("Choose a calendar")
                            .font(.headline)
                            .padding(.top, 12)

                        Picker("Calendar", selection: Binding(
                            get: { selectedCalendarId ?? calendars.first?.id ?? "" },
                            set: { newValue in selectedCalendarId = newValue }
                        )) {
                            ForEach(calendars, id: \.id) { calendar in
                                Text(calendar.title).tag(calendar.id)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxHeight: 280)

                        Button("Save") {
                            if let sel = selectedCalendarId,
                               let calendar = calendars.first(where: { $0.id == sel }) {
                                Task { await selectCalendar(calendar) }
                            }
                            showCalendarPicker = false
                        }
                        .font(.headline.weight(.semibold))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 12)
                    .background(AnimatingBackground().ignoresSafeArea())
                }
                .presentationDetents([.fraction(0.5), .large])
            }
        }
        .ignoresSafeArea()
        .task {
            await prefetchCalendarsIfNeeded()
        }
    }

    private var checklist: some View {
        VStack(spacing: 14) {
            checklistRow(title: "Login", detail: "Sign in to sync your data and purchases.", status: auth.isAuthenticated ? .granted : .pending) {
                // Auth handled elsewhere
            }
            .padding(.top, 4)

            checklistRow(title: "Screen Time access", detail: "Allow Monk to block distractions during focus sessions.", status: screenTimeStatus, isLoading: screenTimeBusy) {
                Task { await requestScreenTime() }
            }

            checklistRow(title: "Calendar access", detail: "Write focus sessions to your calendar.", status: calendarStatusView, isLoading: calendarBusy, grantedActionTitle: calendarButtonTitle) {
                Task { await prepareCalendarSelection(showPicker: true) }
            }

            if let calendarStatus {
                Text(calendarStatus)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            checklistRow(title: "Location access", detail: "Add where you focused to calendar entries.", status: locationStatus, isLoading: locationBusy) {
                Task { await requestLocation() }
            }
        }
    }

    private func checklistRow(title: String,
                              detail: String,
                              status: ChecklistStatus,
                              isLoading: Bool = false,
                              grantedActionTitle: String? = nil,
                              action: @escaping () -> Void) -> some View {
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
            if status == .granted {
                if let grantedActionTitle {
                    Button(action: action) {
                        Text(grantedActionTitle)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Done")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white)
                        .opacity(0.6)
                }
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                Button(action: action) {
                    Text("Enable")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Status helpers

    private var screenTimeStatus: ChecklistStatus {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: return .granted
        case .denied: return .denied
        default: return .pending
        }
    }

    private var calendarStatusView: ChecklistStatus {
        if calendarBusy { return .pending }
        if prefs.calendarIntegrationEnabled == true, let id = prefs.calendarCalendarIdentifier, !id.isEmpty {
            return .granted
        }
        return .pending
    }

    private var calendarButtonTitle: String {
        if let name = selectedCalendarName, !name.isEmpty { return name }
        if let id = prefs.calendarCalendarIdentifier,
           let title = calendars.first(where: { $0.id == id })?.title {
            return title
        }
        return "Select"
    }

    private var locationStatus: ChecklistStatus {
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied, .restricted: return .denied
        default: return .pending
        }
    }

    // MARK: - Actions

    private func requestScreenTime() async {
        await MainActor.run { screenTimeBusy = true }
        _ = await HardBlockManager.shared.ensureAuthorization()
        await MainActor.run { screenTimeBusy = false }
    }

    private func refreshCalendars() async {
        await MainActor.run { calendarBusy = true }
        let options = await CalendarIntegration.shared.availableCalendars()
        await MainActor.run {
            calendars = options
            if selectedCalendarId == nil {
                selectedCalendarId = prefs.calendarCalendarIdentifier
            }
            if let sel = selectedCalendarId,
               let match = options.first(where: { $0.id == sel }) {
                selectedCalendarName = match.title
            }
            calendarBusy = false
        }
    }

    private func prepareCalendarSelection(showPicker: Bool) async {
        await MainActor.run { calendarBusy = true }
        if calendars.isEmpty {
            await refreshCalendars()
        } else {
            await MainActor.run { calendarBusy = false }
        }
        await MainActor.run {
            if calendars.isEmpty {
                calendarStatus = "No writable calendars available. Check iOS Settings > Calendars."
            } else if showPicker {
                selectedCalendarId = prefs.calendarCalendarIdentifier ?? calendars.first?.id
                if let sel = selectedCalendarId,
                   let match = calendars.first(where: { $0.id == sel }) {
                    selectedCalendarName = match.title
                }
                showCalendarPicker = true
            }
        }
    }

    private func selectCalendar(_ calendar: CalendarDisplayInfo) async {
        await MainActor.run {
            prefs.calendarCalendarIdentifier = calendar.id
            prefs.calendarIntegrationEnabled = true
            modelContext.saveOrRollback()
            calendarStatus = nil
            selectedCalendarId = calendar.id
            selectedCalendarName = calendar.title
            calendarBusy = false
        }
    }

    private func requestLocation() async {
        await MainActor.run { locationBusy = true }
        _ = await LocationProvider.shared.requestLocation()
        await MainActor.run { locationBusy = false }
    }

    private func prefetchCalendarsIfNeeded() async {
        guard !didPrefetchCalendars,
              prefs.calendarIntegrationEnabled == true,
              calendars.isEmpty else { return }
        let options = await CalendarIntegration.shared.availableCalendars()
        await MainActor.run {
            calendars = options
            selectedCalendarId = prefs.calendarCalendarIdentifier
            if let sel = selectedCalendarId,
               let match = options.first(where: { $0.id == sel }) {
                selectedCalendarName = match.title
            }
            didPrefetchCalendars = true
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
