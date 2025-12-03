import SwiftUI
import SwiftData
import UserJot

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @EnvironmentObject private var tutorial: TutorialCoordinator
    @EnvironmentObject private var auth: AuthManager
    @Query private var prefsList: [Preferences]
    @Query(sort: [SortDescriptor(\FocusSession.startedAt, order: .forward)]) private var allSessions: [FocusSession]
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)]) private var projects: [Project]

    @State private var calendarOptions: [CalendarDisplayInfo] = []
    @State private var calendarStatusMessage: String?
    @State private var calendarBusy = false
    @State private var calendarHighlight: TutorialHighlightInfo?
    @State private var locationHighlight: TutorialHighlightInfo?
    @State private var feedbackStatusMessage: String?
    @State private var showingFeedback = false
    @State private var selectedBoard: String?
    @State private var showingFeedbackWeb = false

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
                        feedbackCard
                        goalCard
                        calendarCard
                        sessionsCard
                        restartTutorialCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 36)
                }
            }
            .navigationTitle("Settings")
            .overlay {
                if let stage = tutorial.activeStage,
                   stage == .calendar || stage == .location {
                    TutorialOverlayView(
                        stage: stage,
                        highlight: highlight(for: stage),
                        onNext: tutorial.complete,
                        onSkip: tutorial.skip,
                        showActions: false
                    )
                }
            }
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
        .onPreferenceChange(TutorialAnchorPreferenceKey.self) { values in
            for value in values {
                switch value.stage {
                case .calendar:
                    calendarHighlight = TutorialHighlightInfo(stage: value.stage, frame: value.frame, cornerRadius: value.cornerRadius)
                case .location:
                    locationHighlight = TutorialHighlightInfo(stage: value.stage, frame: value.frame, cornerRadius: value.cornerRadius)
                default:
                    break
                }
            }
        }
    }
}

private extension SettingsView {
    func highlight(for stage: TutorialStage) -> TutorialHighlightInfo? {
        switch stage {
        case .calendar:
            return calendarHighlight
        case .location:
            return locationHighlight
        default:
            return nil
        }
    }

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
                    .tutorialAnchor(.calendar, cornerRadius: 14)
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
                .tutorialAnchor(.location, cornerRadius: 14)
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

    var restartTutorialCard: some View {
        SettingsCard(title: "Onboarding",
                     subtitle: "Replay the guided setup anytime.",
                     icon: "sparkles") {
            Button {
                Haptics.heavy()
                preferencesResetOnboarding()
                tutorial.skip()
            } label: {
                Text("Restart tutorial")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
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
            if tutorial.activeStage == .calendar {
                tutorial.complete()
            }
        }
    }

    func requestLocationPermission() async {
        _ = await LocationProvider.shared.requestLocation()
        await MainActor.run {
            calendarStatusMessage = nil
            if tutorial.activeStage == .location {
                tutorial.complete()
            }
        }
    }

    func preferencesResetOnboarding() {
        if let prefs = prefsList.first {
            prefs.onboardingVersion = 0
            prefs.onboardingPendingCardRaw = OnboardingCard.welcome.rawValue
            prefs.onboardingActiveStageRaw = nil
            modelContext.saveOrRollback()
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
