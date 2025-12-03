//
//  ContentView.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import SwiftUI
import SwiftData
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authManager = AuthManager()
    @State private var manager: FocusManager?
    @State private var selectedTab: AppTab = .home
    @StateObject private var tutorial = TutorialCoordinator()
    @Query private var prefsList: [Preferences]
    @State private var currentCard: OnboardingCard?
    @State private var currentLiveStage: TutorialStage?
    @State private var screenTimeStatus: PermissionState = .idle
    @State private var calendarStatus: PermissionState = .idle
    @State private var locationStatus: PermissionState = .idle
    @State private var didTriggerPaywallOnLaunch = false
    @State private var requirePaywall = false
    @State private var screenTimeLoading = false

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if let manager {
                    TabView(selection: $selectedTab) {
                        NavigationStack {
                            HomeView()
                        }
                        .tabItem {
                            Label("", systemImage: "house")
                                .accessibilityLabel("Home")
                        }
                        .tag(AppTab.home)

                        NavigationStack {
                            InsightsView()
                        }
                        .tabItem {
                            Label("", systemImage: "chart.bar.doc.horizontal")
                                .accessibilityLabel("Insights")
                        }
                        .tag(AppTab.insights)

                        NavigationStack {
                            HistoryView()
                        }
                        .tabItem {
                            Label("", systemImage: "clock.arrow.circlepath")
                                .accessibilityLabel("History")
                        }
                        .tag(AppTab.history)

                        NavigationStack {
                            SettingsView()
                        }
                        .tabItem {
                            Label("", systemImage: "gearshape")
                                .accessibilityLabel("Settings")
                        }
                        .tag(AppTab.settings)
                    }
                    .preferredColorScheme(.dark)
                    .tint(.white)
                    .onChange(of: selectedTab) { _, _ in
                        Haptics.heavy()
                    }
                    .environmentObject(manager)
                    .environmentObject(tutorial)
                    .environmentObject(authManager)
                    .onAppear {
                        maybeShowPaywallOnLaunch()
                        tutorial.tabSelectionHandler = { tab in
                            if selectedTab != tab {
                                selectedTab = tab
                            }
                        }
                        startOnboardingIfNeeded()
                        updatePaywallRequirement()
                    }
                    .onChange(of: tutorial.activeStage) { previous, stage in
                        handleTutorialStageChange(previous: previous, current: stage)
                    }
                    .onChange(of: preferences.onboardingVersion) { _, _ in
                        startOnboardingIfNeeded()
                        maybeShowPaywallOnLaunch()
                        updatePaywallRequirement()
                    }
                    .onChange(of: authManager.isAuthenticated) { _, _ in
                        updatePaywallRequirement()
                    }
                    .overlay {
                        if let card = currentCard {
                            OnboardingCardView(
                                card: card,
                                status: status(for: card),
                                onContinue: { handleCardContinue(card) },
                                onSkip: skipAction(for: card),
                                isLoading: card == .screenTime ? screenTimeLoading : false
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
                                    removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .center))
                                )
                            )
                            .animation(.spring(response: 0.26, dampingFraction: 0.85), value: currentCard?.id)
                        }
                    }
                    .fullScreenCover(isPresented: $requirePaywall) {
                        PaywallBlockView {
                            PaywallManager.shared.presentPaywall(force: true)
                        }
                        .interactiveDismissDisabled(true)
                    }
                    .onOpenURL { url in
#if canImport(GoogleSignIn)
                        _ = GIDSignIn.sharedInstance.handle(url)
#endif
                    }
                } else {
                    ProgressView()
                        .task {
                            await MainActor.run { self.manager = FocusManager(modelContext: modelContext) }
                        }
                }
            } else {
                AuthGatewayView()
                    .environmentObject(authManager)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            FocusSession.self,
            Preferences.self,
            Project.self
        ], inMemory: true)
}

private extension ContentView {
    var preferences: Preferences {
        if let existing = prefsList.first { return existing }
        let created = Preferences(hasConvertedDailyGoal: true)
        modelContext.insert(created)
        _ = modelContext.saveOrRollback()
        return created
    }

    var persistedCard: OnboardingCard? {
        preferences.onboardingPendingCardRaw.flatMap { OnboardingCard(rawValue: $0) }
    }

    var persistedStage: TutorialStage? {
        preferences.onboardingActiveStageRaw.flatMap { TutorialStage(rawValue: $0) }
    }

    var shouldShowOnboarding: Bool {
        preferences.onboardingVersion < 1
    }

    func persistCard(_ card: OnboardingCard?) {
        preferences.onboardingPendingCardRaw = card?.rawValue
        _ = modelContext.saveOrRollback()
    }

    func persistStage(_ stage: TutorialStage?) {
        preferences.onboardingActiveStageRaw = stage?.rawValue
        _ = modelContext.saveOrRollback()
    }

    func finishOnboarding() {
        preferences.onboardingVersion = 1
        preferences.onboardingPendingCardRaw = nil
        preferences.onboardingActiveStageRaw = nil
        _ = modelContext.saveOrRollback()
        tutorial.skip()
        currentCard = nil
        currentLiveStage = nil
        resetPermissionStatuses()
        if !PaywallManager.shared.hasAccess {
            PaywallManager.shared.presentPaywall()
        }
        updatePaywallRequirement()
    }

    func startOnboardingIfNeeded() {
        guard authManager.isAuthenticated else { return }
        guard shouldShowOnboarding else { return }
        if let savedStage = persistedStage {
            beginStage(savedStage, persist: false)
        } else if currentCard == nil && tutorial.activeStage == nil && currentLiveStage == nil {
            if persistedCard == .createProject {
                beginStage(.createProject)
            } else {
                let cardToShow = persistedCard ?? .welcome
                currentCard = cardToShow
                persistCard(cardToShow)
            }
            resetPermissionStatuses()
        }
    }

    func handleCardContinue(_ card: OnboardingCard) {
        switch card {
        case .welcome:
            showNextCard(after: card)
        case .projectIntro:
            beginStage(.createProject)
        case .createProject:
            beginStage(.createProject)
        case .sessionExplain:
            showNextCard(after: card)
        case .startSession:
            beginStage(.startSession)
        case .screenTime:
            Task { @MainActor in
                screenTimeLoading = true
                defer { screenTimeLoading = false }
                let granted = await HardBlockManager.shared.ensureAuthorization()
                screenTimeStatus = granted ? .granted : .denied
                if granted {
                    showNextCard(after: card)
                }
            }
        case .calendar:
            Task {
                let granted = await CalendarIntegration.shared.requestAccess()
                await MainActor.run {
                    calendarStatus = granted ? .granted : .denied
                    if granted {
                        showNextCard(after: card)
                    }
                }
            }
        case .location:
            Task { @MainActor in
                let result = await LocationProvider.shared.requestLocation()
                locationStatus = (result != nil) ? .granted : .denied
                if result != nil {
                    showNextCard(after: card)
                }
            }
        case .stopSession:
            beginStage(.stopSession)
        case .insightsExplain:
            beginStage(.insights)
        }
    }

    func handleTutorialStageChange(previous: TutorialStage?, current: TutorialStage?) {
        if let current {
            currentLiveStage = current
            persistStage(current)
            if selectedTab != current.preferredTab {
                selectedTab = current.preferredTab
            }
        } else {
            persistStage(nil)
            let finishedStage = previous ?? currentLiveStage
            currentLiveStage = nil
            if let finishedStage, let next = nextCard(afterStage: finishedStage) {
                currentCard = next
                persistCard(next)
            } else if currentCard == nil {
                finishOnboarding()
            }
        }
    }

    func beginStage(_ stage: TutorialStage, persist: Bool = true) {
        currentCard = nil
        currentLiveStage = stage
        if persist { persistStage(stage) }
        tutorial.start(at: stage)
    }

    func showNextCard(after card: OnboardingCard) {
        let next = nextCard(after: card)
        currentCard = next
        persistCard(next)
        if next == nil && tutorial.activeStage == nil {
            finishOnboarding()
        }
    }

    func status(for card: OnboardingCard) -> OnboardingCardView.Status? {
        switch card {
        case .screenTime:
            return screenTimeStatus.asStatus()
        case .calendar:
            return calendarStatus.asStatus()
        case .location:
            return locationStatus.asStatus()
        default:
            return nil
        }
    }

    func skipAction(for card: OnboardingCard) -> (() -> Void)? {
        switch card {
        case .screenTime, .calendar, .location:
            return { showNextCard(after: card) }
        default:
            return nil
        }
    }

    func nextCard(after card: OnboardingCard?) -> OnboardingCard? {
        guard let card else { return .projectIntro }
        switch card {
        case .welcome: return .screenTime
        case .screenTime: return .projectIntro
        case .projectIntro: return .createProject
        case .createProject: return .sessionExplain
        case .sessionExplain: return .startSession
        case .startSession: return .calendar
        case .calendar: return .location
        case .location: return .stopSession
        case .stopSession: return .insightsExplain
        case .insightsExplain: return nil
        }
    }

    func nextCard(afterStage stage: TutorialStage) -> OnboardingCard? {
        switch stage {
        case .createProject: return .sessionExplain
        case .startSession: return .calendar
        case .stopSession: return .insightsExplain
        case .calendar: return .location
        case .location: return .stopSession
        case .insights: return nil
        case .welcome: return nil
        case .paywall: return nil
        }
    }

    func resetPermissionStatuses() {
        screenTimeStatus = .idle
        calendarStatus = .idle
        locationStatus = .idle
    }

    func maybeShowPaywallOnLaunch() {
        guard !didTriggerPaywallOnLaunch else { return }
        guard onboardingCompleted else { return }
        guard !PaywallManager.shared.hasAccess else { return }
        guard authManager.isAuthenticated else { return }
        didTriggerPaywallOnLaunch = true
        PaywallManager.shared.presentPaywall()
    }

    func updatePaywallRequirement() {
        let shouldRequire = authManager.isAuthenticated
        && onboardingCompleted
        && !PaywallManager.shared.hasAccess
        && !PaywallManager.isDisabled
        requirePaywall = shouldRequire
    }

    private var onboardingCompleted: Bool {
        // Require onboardingVersion >= 1 AND no pending/persisted onboarding state.
        guard preferences.onboardingVersion >= 1 else { return false }
        if preferences.onboardingPendingCardRaw != nil { return false }
        if preferences.onboardingActiveStageRaw != nil { return false }
        if currentCard != nil { return false }
        if tutorial.activeStage != nil { return false }
        if currentLiveStage != nil { return false }
        return true
    }
}

private enum PermissionState {
    case idle, granted, denied

    func asStatus() -> OnboardingCardView.Status? {
        switch self {
        case .idle:
            return nil
        case .granted:
            return OnboardingCardView.Status(text: "Granted", color: .green)
        case .denied:
            return OnboardingCardView.Status(text: "Unavailable", color: .red)
        }
    }
}

private struct PaywallBlockView: View {
    let onPaywall: () -> Void

    var body: some View {
        ZStack {
            AnimatingBackground(base: Theme.settingsBackground(), halo: Theme.settingsHaloGradient)
            VStack(spacing: 20) {
                Spacer()
                VStack(spacing: 10) {
                    Text("Monk Pro Required")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Unlock access to continue using Monk.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                Button {
                    Haptics.heavy()
                    onPaywall()
                } label: {
                    Text("Open Paywall")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(24)
        }
        .ignoresSafeArea()
    }
}
