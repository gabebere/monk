import SwiftUI
import SwiftData
import UserJot

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var revenueCat: RevenueCatService
    @EnvironmentObject private var entitlementSync: EntitlementSyncService
    @Query private var prefsList: [Preferences]
    @Query(sort: [SortDescriptor(\FocusSession.startedAt, order: .forward)]) private var allSessions: [FocusSession]
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)]) private var projects: [Project]
    @AppStorage("telemetry_enabled") private var telemetryEnabled: Bool = true
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var calendarOptions: [CalendarDisplayInfo] = []
    @State private var calendarStatusMessage: String?
    @State private var calendarBusy = false
    @State private var feedbackStatusMessage: String?
    @State private var showingFeedback = false
    @State private var selectedBoard: String?
    @State private var showingFeedbackWeb = false
    @State private var showingOnboardingPreview = false

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
                        accountCard
                        privacyCard
                        feedbackCard
                        goalCard
                        calendarCard
                        sessionsCard
#if DEBUG
                        debugCard
#endif
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
        .sheet(isPresented: $showingOnboardingPreview) {
            OnboardingStoryView { _ in
                showingOnboardingPreview = false
            }
            .environmentObject(auth)
            .environmentObject(focus)
        }
    }
}

private extension SettingsView {
    var goalCard: some View {
        SettingsCard(title: "Project Goals",
                     subtitle: "Weekly targets now come from the sum of all project goals (capped at 112h).",
                     icon: "flag.fill") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%.0fh planned", projectGoalTotal))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Across all projects this week")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("\(String(format: "%.0fh remaining", remainingGoalBudget))", systemImage: "speedometer")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("Cap: 112h/week")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
        }
    }

    var calendarCard: some View {
        SettingsCard(title: "Calendar sync",
                     subtitle: "Sessions are always written to your calendar. Pick which one.",
                     icon: "calendar") {
            VStack(alignment: .leading, spacing: 16) {
                if calendarOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if calendarBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("No writable calendars available. Make sure the account is added in Settings › Calendar and allows edits.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                } else {
                    Picker("Calendar", selection: calendarSelection) {
                        ForEach(calendarOptions) { option in
                            Text("\(option.title) — \(option.sourceName)")
                                .tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accentColor(.white)
                }

                // Status text omitted per request.

                Button {
                    Task { await requestLocationPermission() }
                } label: {
                    Label("Allow location context (optional)", systemImage: "location")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var sessionsCard: some View {
        SettingsCard(title: "Sessions",
                     subtitle: "Keep your history clean by tossing ultra-short focus spurts.",
                     icon: "hourglass") {
            Toggle(isOn: discardShortBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discard sessions under 2 minutes")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
            .tint(Color.cyan)
        }
    }

    var accountCard: some View {
        SettingsCard(title: "Account",
                     subtitle: nil,
                     icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 10) {
                if auth.isAuthenticated {
                    Text("Signed in")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let email = auth.userEmail {
                        Text(email)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    Text("Not signed in")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Button(role: auth.isAuthenticated ? .destructive : .none) {
                    Haptics.heavy()
                    auth.signOut()
                } label: {
                    Text(auth.isAuthenticated ? "Sign out" : "Sign in")
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

    var calendarSelection: Binding<String> {
        Binding(
            get: { prefs.calendarCalendarIdentifier ?? "" },
            set: { newValue in
                let normalized = newValue.isEmpty ? nil : newValue
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

    var rawProjectGoalTotal: Double {
        projects
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
                     subtitle: "Share what’s working and what’s not.",
                     icon: "bubble.left.and.bubble.right.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Haptics.heavy()
                    showingFeedbackWeb = true
                    feedbackStatusMessage = nil
                    print("[UserJot] feedback button tapped; showing web widget")
                } label: {
                    Label("General feedback", systemImage: "square.and.pencil")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                if let feedbackStatusMessage {
                    Text(feedbackStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }

    var privacyCard: some View {
        SettingsCard(title: "Privacy",
                     subtitle: "Control analytics and diagnostics.",
                     icon: "shield.lefthalf.fill") {
            Toggle(isOn: $telemetryEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share anonymous telemetry")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                    Text("Helps improve Monk. No emails or names are sent.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .tint(Color.cyan)
            .onChange(of: telemetryEnabled) { _, newValue in
                Analytics.setEnabled(newValue)
                Analytics.track("settings_toggled", ["key": "telemetry_enabled", "value": newValue])
            }
        }
    }

#if DEBUG
    var debugCard: some View {
        SettingsCard(title: "Debug",
                     subtitle: "Onboarding tools for testing.",
                     icon: "hammer.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Haptics.heavy()
                    Analytics.track("debug_test_event", ["entitlement_active": revenueCat.isPro])
                } label: {
                    Text("Send test analytics event")
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

                Button {
                    Haptics.heavy()
                    showingOnboardingPreview = true
                } label: {
                    Text("Show onboarding (preview)")
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

                Button {
                    Haptics.heavy()
                    hasSeenOnboarding = false
                } label: {
                    Text("Reset onboarding flag")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.heavy()
                    Task {
                        entitlementSync.clear()
                        await revenueCat.resetForDebug()
                    }
                } label: {
                    Text("Reset purchases (debug)")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
#endif
}

private extension SettingsView {
    func refreshCalendars() async {
        let calendars = await CalendarIntegration.shared.availableCalendars()
        await MainActor.run {
            calendarOptions = calendars
            if prefs.calendarCalendarIdentifier == nil,
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
        if let previous, !previous.isEmpty {
            _ = await CalendarIntegration.shared.purgeMonkEvents(in: previous)
        }
        if let newValue, !newValue.isEmpty {
            await CalendarIntegration.shared.backfillSessions(allSessions, calendarIdentifier: newValue)
        }
        await MainActor.run {
            calendarBusy = false
            updateSelectionStatus()
        }
    }

    func requestLocationPermission() async {
        _ = await LocationProvider.shared.requestLocation()
        await MainActor.run {
            calendarStatusMessage = nil
        }
    }

    func removeAllMonkEvents() async {
        await MainActor.run {
            calendarBusy = true
            calendarStatusMessage = nil
        }
        _ = await CalendarIntegration.shared.purgeAllMonkEvents()
        await MainActor.run {
            calendarBusy = false
            calendarStatusMessage = nil
        }
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
