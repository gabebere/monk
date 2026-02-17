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
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]
    @Query(sort: [SortDescriptor(\FocusTask.updatedAt, order: .reverse)]) private var focusTasks: [FocusTask]
    @State private var manager: FocusManager?
    @State private var selectedTab: AppTab = .home
    @State private var guidedTutorialStep: GuidedTutorialStep? = nil

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
                }
                .environmentObject(authManager)
            } else if authManager.isAuthenticated {
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
                    .preferredColorScheme(.dark)
                    .tint(.white)
                    .coordinateSpace(name: "guidedTutorialSpace")
                    .overlayPreferenceValue(GuidedTutorialAnchorPreferenceKey.self) { anchors in
                        GeometryReader { proxy in
                            if let step = guidedTutorialStep {
                                let holes = tutorialHoles(for: step, anchors: anchors, proxy: proxy)
                                GuidedTutorialSpotlightOverlay(
                                    step: step,
                                    holes: holes,
                                    topInset: proxy.safeAreaInsets.top,
                                    blocksTouchesOutsideHoles: !holes.isEmpty,
                                    onSkip: completeGuidedTutorial
                                )
                                .transition(.opacity)
                            }
                        }
                    }
                    .onAppear {
                        startGuidedTutorialIfNeeded(currentSessionActive: manager.currentSession != nil)
                    }
                    .onChange(of: selectedTab) { _, _ in
                        Haptics.heavy()
                    }
                    .onChange(of: activeProjectCount) { _, _ in
                        advanceGuidedTutorialIfNeeded(currentSessionActive: manager.currentSession != nil)
                    }
                    .onChange(of: activeTaskCount) { _, _ in
                        advanceGuidedTutorialIfNeeded(currentSessionActive: manager.currentSession != nil)
                    }
                    .onChange(of: manager.currentSession != nil) { _, hasSession in
                        advanceGuidedTutorialIfNeeded(currentSessionActive: hasSession)
                    }
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
                guidedTutorialStep = nil
            } else {
                startGuidedTutorialIfNeeded(currentSessionActive: manager?.currentSession != nil)
            }
        }
        .onChange(of: archivedProjectsWithGoalsCount) { _, _ in
            normalizeArchivedProjectGoalsIfNeeded()
        }
        .onChange(of: hasSeenOnboarding) { _, _ in
            startGuidedTutorialIfNeeded(currentSessionActive: manager?.currentSession != nil)
        }
        .onChange(of: hasCompletedSetupChecklist) { _, _ in
            startGuidedTutorialIfNeeded(currentSessionActive: manager?.currentSession != nil)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await HealthSyncService.shared.performSyncIfNeeded(modelContext: modelContext)
                }
                normalizeArchivedProjectGoalsIfNeeded()
                startGuidedTutorialIfNeeded(currentSessionActive: manager?.currentSession != nil)
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
    var activeProjectCount: Int {
        projects.filter { !$0.isArchived }.count
    }

    var activeTaskCount: Int {
        focusTasks.filter { !$0.isCompleted }.count
    }

    var archivedProjectsWithGoalsCount: Int {
        projects.filter { $0.isArchived && $0.weeklyGoalHours != nil }.count
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

    func startGuidedTutorialIfNeeded(currentSessionActive: Bool) {
        guard authManager.isAuthenticated,
              hasSeenOnboarding,
              hasCompletedSetupChecklist,
              needsGuidedTutorial,
              !hasCompletedGuidedTutorial else {
            guidedTutorialStep = nil
            return
        }
        guard guidedTutorialStep == nil else { return }

        if currentSessionActive {
            completeGuidedTutorial()
            return
        }

        if activeTaskCount > 0 {
            selectedTab = .home
            guidedTutorialStep = .startFocus
            return
        }

        if activeProjectCount > 0 {
            selectedTab = .home
            guidedTutorialStep = .createTask
            return
        }

        selectedTab = .home
        guidedTutorialStep = .createProject
    }

    func advanceGuidedTutorialIfNeeded(currentSessionActive: Bool) {
        guard let step = guidedTutorialStep, !hasCompletedGuidedTutorial else { return }

        switch step {
        case .createProject:
            if activeProjectCount > 0 {
                selectedTab = .home
                guidedTutorialStep = .createTask
            }
        case .createTask:
            if activeTaskCount > 0 {
                selectedTab = .home
                guidedTutorialStep = .startFocus
            }
        case .startFocus:
            if currentSessionActive {
                completeGuidedTutorial()
            }
        }
    }

    func completeGuidedTutorial() {
        withAnimation(.easeInOut(duration: 0.2)) {
            hasCompletedGuidedTutorial = true
            needsGuidedTutorial = false
            guidedTutorialStep = nil
        }
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
            add(.projectsEmptyCreateButton)
        case .createTask:
            add(.homeNewTaskButton)
            add(.homeEmptyNewTaskButton)
        case .startFocus:
            add(.homeTimeToFocusButton)
            add(.homeFirstTaskRow)
        }

        return holes
    }
}
