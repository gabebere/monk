//
//  ContentView.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import SwiftData
import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authManager = AuthManager()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasCompletedSetupChecklist") private var hasCompletedSetupChecklist = false
    @AppStorage("needsGuidedTutorial") private var needsGuidedTutorial = false
    @AppStorage("hasCompletedGuidedTutorial") private var hasCompletedGuidedTutorial = false
    @AppStorage("guidedTutorialRestartTrigger") private var guidedTutorialRestartTrigger = ""
    @AppStorage(RemindersSyncKeys.enabled) private var remindersSyncEnabled = false
    @AppStorage(RemindersSyncKeys.destinationListIdentifier) private var remindersSyncDestinationListIdentifier = ""
    @AppStorage(RemindersSyncKeys.excludedListIdentifiers) private var remindersSyncExcludedListIdentifiersRaw = ""
    @AppStorage(RemindersSyncKeys.hasSeededGroceriesExclusions) private var remindersHasSeededGroceriesExclusions = false
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]
    @Query(sort: [SortDescriptor(\FocusTask.updatedAt, order: .reverse)]) private var focusTasks: [FocusTask]
    @State private var manager: FocusManager?
    @State private var selectedTab: AppTab = .home
    @State private var guidedTutorialStep: GuidedTutorialStep? = nil
    @State private var guidedTutorialBaselineProjectIDs: Set<UUID> = []
    @State private var guidedTutorialBaselineTaskIDs: Set<UUID> = []
    @State private var guidedTutorialCreatedProjectID: UUID? = nil
    @State private var guidedTutorialCreatedTaskID: UUID? = nil
    @State private var guidedTutorialPresentedModals: Set<GuidedTutorialModalKind> = []

    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                AuthGatewayView()
                    .environmentObject(authManager)
            } else if !hasCompletedSetupChecklist {
                SetupChecklistView {
                    hasCompletedSetupChecklist = true
                    hasSeenOnboarding = true
                    needsGuidedTutorial = true
                    Analytics.track("setup_checklist_completed")
                }
                .environmentObject(authManager)
            } else if authManager.isAuthenticated {
                if let manager {
                    appShellView()
                    .preferredColorScheme(.dark)
                    .tint(.white)
                    .coordinateSpace(name: "guidedTutorialSpace")
                    .overlayPreferenceValue(GuidedTutorialAnchorPreferenceKey.self) { anchors in
                        GeometryReader { proxy in
                            if let step = guidedTutorialStep, !isGuidedTutorialOverlayPaused {
                                let holes = tutorialHoles(for: step, anchors: anchors, proxy: proxy)
                                GuidedTutorialSpotlightOverlay(
                                    step: step,
                                    holes: holes,
                                    topInset: proxy.safeAreaInsets.top,
                                    bottomInset: proxy.safeAreaInsets.bottom,
                                    blocksTouchesOutsideHoles: step == .ready,
                                    onPrimaryAction: step == .ready ? completeGuidedTutorial : nil,
                                    onSkip: completeGuidedTutorial
                                )
                                .transition(.opacity)
                            }
                        }
                    }
                    .onAppear {
                        startGuidedTutorialIfNeeded()
                        refreshGuidedTutorialProgress(currentSessionActive: manager.currentSession != nil)
                    }
                    .onChange(of: selectedTab) { _, _ in
                        guard !FeatureFlags.homeSingleHubEnabled else { return }
                        Haptics.heavy()
                    }
                    .onChange(of: projectIDsSignature) { _, _ in
                        refreshGuidedTutorialProgress(currentSessionActive: manager.currentSession != nil)
                    }
                    .onChange(of: taskIDsSignature) { _, _ in
                        refreshGuidedTutorialProgress(currentSessionActive: manager.currentSession != nil)
                    }
                    .onChange(of: manager.currentSession != nil) { _, hasSession in
                        refreshGuidedTutorialProgress(currentSessionActive: hasSession)
                    }
                    .environment(\.activeGuidedTutorialStep, guidedTutorialStep)
                    .environment(\.guidedTutorialCreatedProjectID, guidedTutorialCreatedProjectID)
                    .environment(\.guidedTutorialCreatedTaskID, guidedTutorialCreatedTaskID)
                    .environment(\.guidedTutorialBaselineProjectIDs, guidedTutorialBaselineProjectIDs)
                    .environment(\.guidedTutorialBaselineTaskIDs, guidedTutorialBaselineTaskIDs)
                    .environment(\.guidedTutorialEventHandler, handleGuidedTutorialEvent(_:))
                    .environmentObject(manager)
                    .environmentObject(authManager)
                    .onOpenURL { url in
#if canImport(GoogleSignIn)
                        _ = GIDSignIn.sharedInstance.handle(url)
#endif
                    }
                } else {
                    ProgressView()
                        .task {
                            await MainActor.run {
                                self.manager = FocusManager(modelContext: modelContext)
                            }
                            await syncRemindersIfNeeded()
                    }
                }
            } else {
                AuthGatewayView()
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            normalizeArchivedProjectGoalsIfNeeded()
        }
        .onChange(of: authManager.isAuthenticated) { _, _ in
            if !authManager.isAuthenticated {
                resetGuidedTutorialRuntime()
            } else {
                startGuidedTutorialIfNeeded()
            }
        }
        .onChange(of: archivedProjectsWithGoalsCount) { _, _ in
            normalizeArchivedProjectGoalsIfNeeded()
        }
        .onChange(of: hasSeenOnboarding) { _, _ in
            startGuidedTutorialIfNeeded()
        }
        .onChange(of: hasCompletedSetupChecklist) { _, _ in
            startGuidedTutorialIfNeeded()
        }
        .onChange(of: needsGuidedTutorial) { _, _ in
            startGuidedTutorialIfNeeded()
        }
        .onChange(of: hasCompletedGuidedTutorial) { _, _ in
            startGuidedTutorialIfNeeded()
        }
        .onChange(of: guidedTutorialRestartTrigger) { _, _ in
            forceRestartGuidedTutorialFromDebug()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UsageAnalyticsService.shared.trackAppOpenedIfNeeded()
                UsageAnalyticsService.shared.trackDailyFocusSnapshotIfNeeded(
                    totalSeconds: manager?.todayTotalSeconds ?? 0,
                    source: "scene_active"
                )
                Task {
                    await HealthSyncService.shared.performSyncIfNeeded(modelContext: modelContext)
                }
                Task {
                    await syncRemindersIfNeeded()
                }
                Task { @MainActor in
                    await FocusNudgeScheduler.shared.refresh(
                        modelContext: modelContext,
                        currentSession: manager?.currentSession,
                        reason: "scene_active"
                    )
                }
                normalizeArchivedProjectGoalsIfNeeded()
                startGuidedTutorialIfNeeded()
                refreshGuidedTutorialProgress(currentSessionActive: manager?.currentSession != nil)
            }
        }
    }
}

#Preview {
            ContentView()
            .modelContainer(for: [
                FocusSession.self,
                Preferences.self,
                Project.self,
                FocusTask.self,
                HealthSampleLink.self
            ], inMemory: true)
}

private extension ContentView {
    @ViewBuilder
    func appShellView() -> some View {
        if FeatureFlags.homeSingleHubEnabled {
            NavigationStack {
                HomeView()
            }
        } else {
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
                    Label("", systemImage: "chart.bar")
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
        }
    }

    var normalizedRemindersSyncDestinationListIdentifier: String? {
        RemindersSyncStorage.normalizedIdentifier(remindersSyncDestinationListIdentifier)
    }

    var normalizedRemindersSyncExcludedListIdentifiers: Set<String> {
        RemindersSyncStorage.decodeIdentifierSet(remindersSyncExcludedListIdentifiersRaw)
    }

    var projectIDsSignature: String {
        projects.map(\.id).map(\.uuidString).sorted().joined(separator: "|")
    }

    var taskIDsSignature: String {
        focusTasks.map(\.id).map(\.uuidString).sorted().joined(separator: "|")
    }

    var archivedProjectsWithGoalsCount: Int {
        projects.filter { $0.isArchived && $0.weeklyGoalHours != nil }.count
    }

    var allProjectIDs: Set<UUID> {
        Set(projects.map(\.id))
    }

    var allTaskIDs: Set<UUID> {
        Set(focusTasks.map(\.id))
    }

    var newlyCreatedProjects: [Project] {
        projects
            .filter { !guidedTutorialBaselineProjectIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var tutorialSuggestedTaskID: UUID? {
        focusTasks
            .filter(\.isScheduled)
            .filter(\.isReminderBacked)
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                let leftDue = lhs.dueDate ?? .distantFuture
                let rightDue = rhs.dueDate ?? .distantFuture
                if leftDue != rightDue {
                    return leftDue < rightDue
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first?
            .id
    }

    var isGuidedTutorialOverlayPaused: Bool {
        !guidedTutorialPresentedModals.isEmpty
    }

    func normalizeArchivedProjectGoalsIfNeeded() {
        var didMutate = false
        for project in projects where project.isArchived && project.weeklyGoalHours != nil {
            project.weeklyGoalHours = nil
            didMutate = true
        }
        if didMutate {
            modelContext.saveOrRollback()
        }
    }

    @MainActor
    func syncRemindersIfNeeded() async {
        guard remindersSyncEnabled else { return }
        await seedRemindersGroceriesExclusionsIfNeeded()
        await RemindersSyncService.shared.sync(
            modelContext: modelContext,
            destinationListIdentifier: normalizedRemindersSyncDestinationListIdentifier,
            excludedListIdentifiers: normalizedRemindersSyncExcludedListIdentifiers
        )
    }

    @MainActor
    func seedRemindersGroceriesExclusionsIfNeeded() async {
        guard !remindersHasSeededGroceriesExclusions else { return }
        let lists = await RemindersSyncService.shared.availableLists()
        let seeded = RemindersSyncStorage.seededGroceriesExclusions(
            current: normalizedRemindersSyncExcludedListIdentifiers,
            hasSeeded: remindersHasSeededGroceriesExclusions,
            availableLists: lists
        )
        remindersSyncExcludedListIdentifiersRaw = RemindersSyncStorage.encodeIdentifierSet(seeded.identifiers)
        remindersHasSeededGroceriesExclusions = seeded.hasSeeded
    }

    func startGuidedTutorialIfNeeded() {
        guard authManager.isAuthenticated,
              hasSeenOnboarding,
              hasCompletedSetupChecklist,
              needsGuidedTutorial,
              !hasCompletedGuidedTutorial else {
            resetGuidedTutorialRuntime()
            return
        }
        guard guidedTutorialStep == nil else { return }

        selectedTab = .home
        guidedTutorialBaselineProjectIDs = allProjectIDs
        guidedTutorialBaselineTaskIDs = allTaskIDs
        guidedTutorialCreatedProjectID = nil
        guidedTutorialCreatedTaskID = nil
        guidedTutorialPresentedModals = []
        guidedTutorialStep = .createProject
    }

    func refreshGuidedTutorialProgress(currentSessionActive: Bool) {
        guard let step = guidedTutorialStep, !hasCompletedGuidedTutorial else { return }
        selectedTab = .home

        if step != .createProject,
           let createdProjectID = guidedTutorialCreatedProjectID,
           !allProjectIDs.contains(createdProjectID) {
            guidedTutorialCreatedProjectID = nil
            guidedTutorialCreatedTaskID = nil
            guidedTutorialStep = .createProject
            return
        }

        switch step {
        case .createProject:
            if guidedTutorialCreatedProjectID == nil,
               let created = newlyCreatedProjects.first {
                guidedTutorialCreatedProjectID = created.id
                guidedTutorialStep = .openTasks
            }
        case .openTasks:
            break
        case .createTask:
            guidedTutorialCreatedTaskID = tutorialSuggestedTaskID
            if guidedTutorialCreatedTaskID == nil {
                guidedTutorialStep = .startFocusChoice
            }
        case .startFocusChoice, .startFocusButtonOnly:
            if let createdTaskID = guidedTutorialCreatedTaskID,
               !allTaskIDs.contains(createdTaskID) {
                guidedTutorialCreatedTaskID = tutorialSuggestedTaskID
                if guidedTutorialCreatedTaskID == nil {
                    guidedTutorialStep = .startFocusChoice
                } else if step == .startFocusButtonOnly {
                    guidedTutorialStep = .createTask
                }
            }
        case .stopFocus:
            if !currentSessionActive,
               !guidedTutorialPresentedModals.contains(.completedSession) {
                guidedTutorialStep = .ready
            }
        case .finishSession, .ready:
            break
        }
    }

    func completeGuidedTutorial() {
        withAnimation(.easeInOut(duration: 0.2)) {
            hasCompletedGuidedTutorial = true
            needsGuidedTutorial = false
            resetGuidedTutorialRuntime()
        }
        Analytics.track("guided_tutorial_completed")
    }

    func resetGuidedTutorialRuntime() {
        guidedTutorialStep = nil
        guidedTutorialBaselineProjectIDs = []
        guidedTutorialBaselineTaskIDs = []
        guidedTutorialCreatedProjectID = nil
        guidedTutorialCreatedTaskID = nil
        guidedTutorialPresentedModals = []
    }

    func forceRestartGuidedTutorialFromDebug() {
        guard authManager.isAuthenticated else { return }
        hasSeenOnboarding = true
        hasCompletedSetupChecklist = true
        needsGuidedTutorial = true
        hasCompletedGuidedTutorial = false
        resetGuidedTutorialRuntime()
        selectedTab = .home
        startGuidedTutorialIfNeeded()
        refreshGuidedTutorialProgress(currentSessionActive: manager?.currentSession != nil)
    }

    func handleGuidedTutorialEvent(_ event: GuidedTutorialEvent) {
        guard let step = guidedTutorialStep, !hasCompletedGuidedTutorial else { return }

        switch event {
        case .homeSectionChanged(let section):
            if step == .openTasks, section == .tasks {
                guidedTutorialCreatedTaskID = tutorialSuggestedTaskID
                guidedTutorialStep = .createTask
            }
        case .modalChanged(let kind, let isPresented):
            if isPresented {
                guidedTutorialPresentedModals.insert(kind)
            } else {
                guidedTutorialPresentedModals.remove(kind)
            }
        case .focusStarted(let projectID, let taskID):
            switch step {
            case .createTask:
                if taskID != nil || projectID != nil {
                    guidedTutorialStep = .stopFocus
                }
            case .startFocusChoice:
                if taskID != nil || projectID != nil {
                    guidedTutorialStep = .stopFocus
                }
            case .startFocusButtonOnly:
                if taskID != nil {
                    guidedTutorialStep = .stopFocus
                }
            default:
                break
            }
        case .focusStopped(let willShowCompletionSheet):
            guard step == .stopFocus else { break }
            guidedTutorialStep = willShowCompletionSheet ? .finishSession : .ready
        case .completionDone:
            if step == .finishSession {
                guidedTutorialStep = .ready
            }
        }

        refreshGuidedTutorialProgress(currentSessionActive: manager?.currentSession != nil)
    }

    func tutorialHoles(for step: GuidedTutorialStep,
                       anchors: [GuidedTutorialAnchor: Anchor<CGRect>],
                       proxy: GeometryProxy) -> [CGRect] {
        var holes: [CGRect] = []
        func add(_ anchor: GuidedTutorialAnchor) {
            if let frame = anchors[anchor].map({ proxy[$0] }) {
                holes.append(frame)
            }
        }

        switch step {
        case .createProject:
            add(.projectsAddButton)
            add(.projectsContentArea)
            add(.projectsEmptyCreateButton)
        case .openTasks:
            add(.homeTasksSectionButton)
        case .createTask:
            if let createdTaskID = guidedTutorialCreatedTaskID {
                add(.homeTaskRow(createdTaskID))
            } else {
                add(.projectsContentArea)
            }
        case .startFocusChoice:
            add(.projectsContentArea)
            if let createdTaskID = guidedTutorialCreatedTaskID {
                add(.homeTaskRow(createdTaskID))
            }
        case .startFocusButtonOnly:
            if let createdTaskID = guidedTutorialCreatedTaskID {
                add(.homeTaskRow(createdTaskID))
            } else {
                add(.projectsContentArea)
            }
        case .stopFocus:
            add(.homeStopButton)
        case .finishSession, .ready:
            break
        }

        return holes
    }
}
