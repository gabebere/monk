import SwiftUI
import FamilyControls
import CoreLocation
import SwiftData
import UserNotifications
import UIKit
import HealthKit
import EventKit

struct SetupChecklistView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthManager
    @State private var calendars: [CalendarDisplayInfo] = []
    @State private var calendarStatus: String?
    @State private var calendarBusy = false
    @State private var screenTimeBusy = false
    @State private var locationBusy = false
    @State private var showCalendarPicker = false
    @State private var selectedCalendarId: String?
    @State private var selectedCalendarName: String?
    @State private var didPrefetchCalendars = false
    @State private var notificationsStatus: ChecklistStatus = .pending
    @State private var notificationsBusy = false
    @State private var healthStatus: ChecklistStatus = .pending
    @State private var healthBusy = false

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
                    Text("Some Technicalities...")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    checklist

                    Spacer()

                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.large)
                    .tint(Color.white.opacity(0.22))
                    .foregroundStyle(.white)
                    .disabled(!canFinishChecklist)
                    .opacity(canFinishChecklist ? 1 : 0.6)

                    if !canFinishChecklist {
                        Text("Continue through Calendar, Health, and Location prompts to proceed.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCalendarPicker) {
                NavigationStack {
                    Group {
                        if calendarBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if calendars.isEmpty {
                            Text("No writable calendars available.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(calendars, id: \.id) { calendar in
                                Button {
                                    selectedCalendarId = calendar.id
                                } label: {
                                    HStack {
                                        Text(calendar.title)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if selectedCalendarId == calendar.id {
                                            Image(systemName: "checkmark")
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                            }
                            .scrollContentBackground(.hidden)
                            .listStyle(.insetGrouped)
                        }
                    }
                    .navigationTitle("Choose a calendar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showCalendarPicker = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                if let sel = selectedCalendarId,
                                   let calendar = calendars.first(where: { $0.id == sel }) {
                                    Task { await selectCalendar(calendar) }
                                }
                                showCalendarPicker = false
                            }
                            .disabled(calendars.isEmpty || selectedCalendarId == nil || calendarBusy)
                        }
                    }
                }
                .presentationDetents([.fraction(0.5), .large])
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea()
        .task {
            await prefetchCalendarsIfNeeded()
            await refreshNotificationStatus()
            await refreshHealthStatus()
        }
    }

    private var checklist: some View {
        VStack(spacing: 14) {
            checklistRow(title: "Login", detail: "Sign in to sync your data across devices.", status: auth.isAuthenticated ? .granted : .pending) {
                // Auth handled elsewhere
            }
            .padding(.top, 4)

            checklistRow(title: "Screen Time access", detail: "Allow Monk to block distractions during focus sessions.", status: screenTimeStatus, isLoading: screenTimeBusy) {
                Task { await requestScreenTime() }
            }

            checklistRow(title: "Calendar access", detail: "Write focus sessions to your calendar.", status: calendarStatusView, isLoading: calendarBusy, grantedActionTitle: calendarButtonTitle) {
                Task { await prepareCalendarSelection(showPicker: true) }
            }

            checklistRow(title: "Notifications", detail: "Get reminders and updates across devices.", status: notificationsStatus, isLoading: notificationsBusy) {
                Task { await requestNotifications() }
            }

            checklistRow(title: "Health access", detail: "Import workouts and sleep into your calendar.", status: healthStatus, isLoading: healthBusy) {
                Task { await requestHealthAccess() }
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
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(Color.white.opacity(0.2))
                    .foregroundStyle(.white)
                } else {
                    Button("Done") {}
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(Color.white.opacity(0.2))
                        .foregroundStyle(.white)
                        .disabled(true)
                        .opacity(0.7)
                }
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                Button(action: action) {
                    Text("Continue")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Color.white.opacity(0.2))
                .foregroundStyle(.white)
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

    private var calendarPermissionStatus: ChecklistStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess, .writeOnly:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .pending
        @unknown default:
            return .pending
        }
    }

    private var calendarStatusView: ChecklistStatus {
        if calendarBusy { return .pending }
        return calendarPermissionStatus
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

    private var canFinishChecklist: Bool {
        calendarPermissionStatus != .pending &&
        healthStatus != .pending &&
        locationStatus != .pending
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

    private func requestHealthAccess() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            await MainActor.run {
                healthStatus = .granted
                healthBusy = false
            }
            return
        }
        await MainActor.run { healthBusy = true }
        do {
            try await HKHealthStore().requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), sleepType])
            await MainActor.run {
                prefs.healthIncludeWorkouts = true
                prefs.healthIncludeSleepAsleep = true
                prefs.healthIncludeSleepInBed = true
                modelContext.saveOrRollback()
            }
            await refreshHealthStatus()
        } catch {
            await MainActor.run {
                healthStatus = .pending
                healthBusy = false
            }
        }
    }

    private func refreshHealthStatus() async {
        let hasEnabledHealthImport = prefs.healthIncludeWorkouts || prefs.healthIncludeSleepAsleep || prefs.healthIncludeSleepInBed
        if hasEnabledHealthImport {
            await MainActor.run {
                healthStatus = .granted
                healthBusy = false
            }
            return
        }

        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            await MainActor.run {
                healthStatus = .granted
                healthBusy = false
            }
            return
        }
        let store = HKHealthStore()
        let sleepStatus = store.authorizationStatus(for: sleepType)
        let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        let hasDeterminedStatus = sleepStatus != .notDetermined || workoutStatus != .notDetermined
        await MainActor.run {
            // HealthKit read-access verification can be ambiguous; show success once a choice was made.
            healthStatus = hasDeterminedStatus ? .granted : .pending
            healthBusy = false
        }
    }

    private func requestLocation() async {
        await MainActor.run { locationBusy = true }
        _ = await LocationProvider.shared.requestLocation()
        await MainActor.run { locationBusy = false }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationsStatus = mapNotificationStatus(settings)
        }
    }

    private func requestNotifications() async {
        await MainActor.run { notificationsBusy = true }
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            await MainActor.run {
                notificationsStatus = .denied
                notificationsBusy = false
            }
            FocusNudgeScheduler.shared.clearAll()
            return
        }
        await refreshNotificationStatus()
        await MainActor.run { notificationsBusy = false }
        if granted {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await FocusNudgeScheduler.shared.refresh(
                modelContext: modelContext,
                currentSession: nil,
                reason: "setup_notifications_granted"
            )
        } else {
            FocusNudgeScheduler.shared.clearAll()
        }
    }

    private func mapNotificationStatus(_ settings: UNNotificationSettings) -> ChecklistStatus {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .pending
        @unknown default:
            return .pending
        }
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
