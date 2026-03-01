import SwiftUI
import SwiftData
import UserJot

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @EnvironmentObject private var auth: AuthManager
    @Query private var prefsList: [Preferences]
    @Query(sort: [SortDescriptor(\FocusSession.startedAt, order: .forward)]) private var allSessions: [FocusSession]
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)]) private var projects: [Project]
    @AppStorage("telemetry_enabled") private var telemetryEnabled: Bool = true
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasCompletedSetupChecklist") private var hasCompletedSetupChecklist = false
    @AppStorage("needsGuidedTutorial") private var needsGuidedTutorial = false
    @AppStorage("hasCompletedGuidedTutorial") private var hasCompletedGuidedTutorial = false
    @AppStorage("guidedTutorialRestartTrigger") private var guidedTutorialRestartTrigger = ""

    @State private var calendarOptions: [CalendarDisplayInfo] = []
    @State private var calendarStatusMessage: String?
    @State private var calendarBusy = false
    @State private var showingFeedbackWeb = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var deleteAccountBusy = false
    @State private var deleteAccountStatusMessage: String?
    @AppStorage("mirroring.enabled") private var mirroringEnabled: Bool = true
    @AppStorage("calendar.logging.enabled") private var calendarLoggingEnabled: Bool = true

    private var prefs: Preferences {
        if let existing = prefsList.first {
            var didChange = false
            if existing.weeklyGoalHours < 0 {
                existing.weeklyGoalHours = 0
                didChange = true
            }
            if !existing.hasConvertedDailyGoal {
                if existing.weeklyGoalHours > 0 && existing.weeklyGoalHours <= 24 {
                    existing.weeklyGoalHours = existing.weeklyGoalHours * 7
                }
                existing.hasConvertedDailyGoal = true
                didChange = true
            }
            if didChange {
                modelContext.saveOrRollback()
            }
            return existing
        }
        let created = Preferences(hasConvertedDailyGoal: true)
        modelContext.insert(created)
        return created
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatingBackground(base: Theme.settingsBackground(), halo: Theme.settingsHaloGradient)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        feedbackCard
                        mirroringCard
                        calendarCard
                        healthCard
                        goalCard
                        sessionsCard
                        debugTutorialCard
                        accountCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 36)
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            await refreshCalendars()
        }
        .sheet(isPresented: $showingFeedbackWeb) {
            FeedbackWebView(
                projectId: "cmiptfvv400yb15lbz1dzqbey",
                userId: auth.currentUserId ?? UUID().uuidString,
                email: auth.userEmail ?? "gabriel@monk.app",
                firstName: auth.displayName,
                lastName: nil,
                signature: UserJotSigner.signature(for: auth.currentUserId ?? UUID().uuidString),
                onClose: { showingFeedbackWeb = false }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog("Delete account permanently?",
                            isPresented: $showingDeleteAccountConfirmation,
                            titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your account data from this device and signs you out.")
        }
    }
}

private extension SettingsView {
    var goalCard: some View {
        SettingsCard(title: "Project goals",
                     subtitle: nil,
                     icon: "flag.fill") {
            HStack {
                Text(String(format: "%.0fh planned", projectGoalTotal))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.0fh left", remainingGoalBudget))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text("Goals come from projects (max 112h/week).")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    var calendarCard: some View {
        SettingsCard(title: "Calendar",
                     subtitle: nil,
                     icon: "calendar") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $calendarLoggingEnabled) {
                    Text("Create calendar events from this device")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .tint(.cyan)
                .onChange(of: calendarLoggingEnabled) { old, newValue in
                    if newValue, old == false {
                        resumeCalendarBackfillIfNeeded()
                    }
                }

                if calendarLoggingEnabled {
                    Picker("Calendar", selection: calendarSelection) {
                        Text("None").tag(String?.none)
                        ForEach(calendarOptions) { option in
                            Text(option.title)
                                .tag(Optional<String>.some(option.id))
                        }
                        if let orphanTag = orphanedSelectionTag {
                            Text("Unavailable (\(orphanTag))").tag(Optional<String>.some(orphanTag))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.white)
                    .disabled(calendarBusy)
                    if calendarOptions.isEmpty && !calendarBusy {
                        Text("No writable calendars available. Add one in Calendar settings.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Toggle(isOn: discardShortBinding) {
                    Text("Discard sessions under 2 minutes")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .tint(.cyan)
            }
        }
    }

    var healthCard: some View {
        SettingsCard(title: "Health sync",
                     subtitle: "Read-only; refreshed on app launch.",
                     icon: "heart.fill") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: healthWorkoutsBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workouts → calendar")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Imports last 30 days; new items auto-sync.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .tint(.pink)

                if prefs.healthIncludeWorkouts {
                    Picker("Assign to project (optional)", selection: workoutProjectBinding) {
                        Text("None").tag(UUID?.none)
                        ForEach(projects) { project in
                            Text(project.title).tag(Optional<UUID>.some(project.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    Button {
                        Task {
                            await HealthSyncService.shared.removeImportedEvents(kinds: [.workout],
                                                                                calendarId: prefs.calendarCalendarIdentifier,
                                                                                modelContext: modelContext)
                        }
                    } label: {
                        Label("Remove imported workouts", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Toggle(isOn: healthAsleepBinding) {
                    Text("Time asleep → calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .tint(.pink)
                if prefs.healthIncludeSleepAsleep {
                    Button {
                        Task {
                            await HealthSyncService.shared.removeImportedEvents(kinds: [.sleepAsleep],
                                                                                calendarId: prefs.calendarCalendarIdentifier,
                                                                                modelContext: modelContext)
                        }
                    } label: {
                        Label("Remove imported sleep (asleep)", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Toggle(isOn: healthInBedBinding) {
                    Text("Time in bed → calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .tint(.pink)
                if prefs.healthIncludeSleepInBed {
                    Button {
                        Task {
                            await HealthSyncService.shared.removeImportedEvents(kinds: [.sleepInBed],
                                                                                calendarId: prefs.calendarCalendarIdentifier,
                                                                                modelContext: modelContext)
                        }
                    } label: {
                        Label("Remove imported sleep (in bed)", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Text("Last import")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(lastHealthImportLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Button {
                    Haptics.heavy()
                    prefs.healthLastImportAt = nil
                    modelContext.saveOrRollback()
                    Task {
                        await HealthSyncService.shared.performSyncIfNeeded(modelContext: modelContext, forceFullResync: true)
                    }
                } label: {
                    Label("Sync now", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var sessionsCard: some View {
        SettingsCard(title: "Data",
                     subtitle: nil,
                     icon: "shield.lefthalf.fill") {
            Toggle(isOn: $telemetryEnabled) {
                Text("Share anonymous telemetry")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .tint(Color.cyan)
            .onChange(of: telemetryEnabled) { _, newValue in
                Analytics.setEnabled(newValue)
                Analytics.track("settings_toggled", ["key": "telemetry_enabled", "value": newValue])
            }
        }
    }

    var mirroringCard: some View {
        SettingsCard(title: "Session mirroring",
                     subtitle: "Sync live sessions across your devices.",
                     icon: "wifi") {
            Toggle(isOn: $mirroringEnabled) {
                Text("This device participates in mirroring")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .tint(Color.cyan)
            .onChange(of: mirroringEnabled) { _, newValue in
                MirrorSyncService.shared.setParticipation(enabled: newValue)
            }
        }
    }

    var accountCard: some View {
        SettingsCard(title: "Account",
                     subtitle: nil,
                     icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if auth.isAuthenticated {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(auth.displayName ?? "Signed in")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                            if let email = auth.userEmail {
                                Text(email)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    } else {
                        Text("Not signed in")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button(role: auth.isAuthenticated ? .destructive : .none) {
                        Haptics.heavy()
                        auth.signOut()
                    } label: {
                        Text(auth.isAuthenticated ? "Sign out" : "Sign in")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(deleteAccountBusy)
                }

                if auth.isAuthenticated {
                    Button(role: .destructive) {
                        Haptics.heavy()
                        showingDeleteAccountConfirmation = true
                    } label: {
                        HStack(spacing: 10) {
                            if deleteAccountBusy {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(deleteAccountBusy ? "Deleting account..." : "Delete account permanently")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.red.opacity(0.45), lineWidth: 1)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(deleteAccountBusy)

                    Text("This action is permanent and clears your account data from this device.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    if let deleteAccountStatusMessage {
                        Text(deleteAccountStatusMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    var discardShortBinding: Binding<Bool> {
        Binding(
            get: { prefs.discardShortSessions ?? false },
            set: { newValue in
                prefs.discardShortSessions = newValue
                let didSave = modelContext.saveOrRollback()
                if newValue && didSave {
                    focus.purgeShortSessionsIfNeeded()
                }
            }
        )
    }

    var healthWorkoutsBinding: Binding<Bool> {
        Binding(
            get: { prefs.healthIncludeWorkouts },
            set: { newValue in
                prefs.healthIncludeWorkouts = newValue
                modelContext.saveOrRollback()
                if newValue {
                    Task { await HealthSyncService.shared.performSyncIfNeeded(modelContext: modelContext) }
                }
            }
        )
    }

    var healthAsleepBinding: Binding<Bool> {
        Binding(
            get: { prefs.healthIncludeSleepAsleep },
            set: { newValue in
                prefs.healthIncludeSleepAsleep = newValue
                modelContext.saveOrRollback()
                if newValue {
                    Task { await HealthSyncService.shared.performSyncIfNeeded(modelContext: modelContext) }
                }
            }
        )
    }

    var healthInBedBinding: Binding<Bool> {
        Binding(
            get: { prefs.healthIncludeSleepInBed },
            set: { newValue in
                prefs.healthIncludeSleepInBed = newValue
                modelContext.saveOrRollback()
                if newValue {
                    Task { await HealthSyncService.shared.performSyncIfNeeded(modelContext: modelContext) }
                }
            }
        )
    }

    var workoutProjectBinding: Binding<UUID?> {
        Binding(
            get: { prefs.healthDefaultWorkoutProjectId },
            set: { newValue in
                prefs.healthDefaultWorkoutProjectId = newValue
                modelContext.saveOrRollback()
            }
        )
    }

    var lastHealthImportLabel: String {
        if let date = prefs.healthLastImportAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "Not yet synced"
    }

    var calendarSelection: Binding<String?> {
        Binding(
            get: {
                let current = prefs.calendarCalendarIdentifier
                if let current, calendarOptions.contains(where: { $0.id == current }) {
                    return current
                }
                if let current {
                    return current // allow orphaned selection to render
                }
                return nil
            },
            set: { newValue in
                let normalized = newValue?.isEmpty == true ? nil : newValue
                guard prefs.calendarCalendarIdentifier != normalized else { return }
                let previous = prefs.calendarCalendarIdentifier
                prefs.calendarCalendarIdentifier = normalized
                prefs.calendarIntegrationEnabled = normalized != nil
                modelContext.saveOrRollback()
                Task {
                    await handleCalendarSelectionChange(from: previous, to: normalized)
                }
            }
        )
    }

    var orphanedSelectionTag: String? {
        guard let current = prefs.calendarCalendarIdentifier else { return nil }
        return calendarOptions.contains(where: { $0.id == current }) ? nil : current
    }

    var rawProjectGoalTotal: Double {
        projects
            .filter(\.canTrackWeeklyGoal)
            .compactMap { $0.weeklyGoalHours }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    var projectGoalTotal: Double { min(rawProjectGoalTotal, 112) }

    var remainingGoalBudget: Double {
        max(0, 112 - rawProjectGoalTotal)
    }

    var feedbackCard: some View {
        SettingsCard(title: "Feedback",
                     subtitle: "Request features or report bugs.",
                     icon: "sparkles") {
            Button {
                Haptics.heavy()
                showingFeedbackWeb = true
            } label: {
                Text("I have some!")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    var debugTutorialCard: some View {
        SettingsCard(title: "Guided tutorial",
                     subtitle: "Replay the app walkthrough anytime.",
                     icon: "questionmark.circle.fill") {
            Button {
                Haptics.heavy()
                restartGuidedTutorial()
            } label: {
                Text("Restart guided tutorial")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }
}

private extension SettingsView {
    func refreshCalendars() async {
        let calendars = await CalendarIntegration.shared.availableCalendars()
        await MainActor.run {
            calendarOptions = calendars
            if calendarLoggingEnabled,
               prefs.calendarCalendarIdentifier == nil,
               prefs.calendarIntegrationEnabled != false,
               let first = calendars.first {
                prefs.calendarCalendarIdentifier = first.id
                modelContext.saveOrRollback()
            }
        }
        await MainActor.run {
            updateSelectionStatus()
        }
    }

    @MainActor
    func updateSelectionStatus() {
        // Suppress status text per request.
        calendarStatusMessage = nil
    }

    func handleCalendarSelectionChange(from previous: String?, to newValue: String?) async {
        await MainActor.run {
            calendarBusy = true
            calendarStatusMessage = nil
        }
        if calendarLoggingEnabled {
            if let previous, !previous.isEmpty {
                _ = await CalendarIntegration.shared.purgeMonkEvents(in: previous)
            }
            if let newValue, !newValue.isEmpty {
                await CalendarIntegration.shared.backfillSessions(allSessions, calendarIdentifier: newValue)
            }
        }
        await MainActor.run {
            calendarBusy = false
            updateSelectionStatus()
        }
    }

    func resumeCalendarBackfillIfNeeded() {
        guard calendarLoggingEnabled,
              let current = prefs.calendarCalendarIdentifier else { return }
        Task {
            await handleCalendarSelectionChange(from: nil, to: current)
        }
    }

    func restartGuidedTutorial() {
        hasSeenOnboarding = true
        hasCompletedSetupChecklist = true
        needsGuidedTutorial = true
        hasCompletedGuidedTutorial = false
        guidedTutorialRestartTrigger = UUID().uuidString
    }

    func deleteAccount() async {
        guard !deleteAccountBusy else { return }
        deleteAccountBusy = true
        deleteAccountStatusMessage = nil

        focus.abandonCurrentSessionForAccountDeletion()
        HardBlockManager.shared.deactivateHardBlock()

        let healthLinks = (try? modelContext.fetch(FetchDescriptor<HealthSampleLink>())) ?? []
        for link in healthLinks {
            if let eventIdentifier = link.eventIdentifier {
                await CalendarIntegration.shared.deleteEvent(identifier: eventIdentifier)
            }
        }
        _ = await CalendarIntegration.shared.purgeAllMonkEvents()

        guard purgeSwiftDataModels() else {
            deleteAccountStatusMessage = "Unable to delete local account data. Please try again."
            deleteAccountBusy = false
            return
        }
        focus.refreshAfterDataReset()
        deleteAccountBusy = false
        deleteAccountStatusMessage = nil
        auth.deleteAccount()
    }

    @discardableResult
    func purgeSwiftDataModels() -> Bool {
        let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        let tasks = (try? modelContext.fetch(FetchDescriptor<FocusTask>())) ?? []
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        let links = (try? modelContext.fetch(FetchDescriptor<HealthSampleLink>())) ?? []
        let preferences = (try? modelContext.fetch(FetchDescriptor<Preferences>())) ?? []

        sessions.forEach(modelContext.delete)
        tasks.forEach(modelContext.delete)
        projects.forEach(modelContext.delete)
        links.forEach(modelContext.delete)
        preferences.forEach(modelContext.delete)
        return modelContext.saveOrRollback()
    }
}

#Preview {
    SettingsView()
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer()
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }
}
