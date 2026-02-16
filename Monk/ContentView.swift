//
//  ContentView.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import SwiftData
import SwiftUI
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authManager = AuthManager()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasCompletedSetupChecklist") private var hasCompletedSetupChecklist = false
    @State private var manager: FocusManager?
    @State private var selectedTab: AppTab = .home

    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                AuthGatewayView()
                    .environmentObject(authManager)
            } else if !hasCompletedSetupChecklist && !hasSeenOnboarding {
                SetupChecklistView {
                    hasCompletedSetupChecklist = true
                }
                .environmentObject(authManager)
            } else if !hasSeenOnboarding {
                OnboardingStoryView {
                    hasSeenOnboarding = true
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

                        if shouldShowProjectsTab {
                            NavigationStack {
                                ProjectsTabView()
                            }
                            .tabItem {
                                Label("", systemImage: "square.grid.2x2")
                                    .accessibilityLabel("Projects")
                            }
                            .tag(AppTab.projects)
                        }

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
                    .onChange(of: shouldShowProjectsTab) { _, visible in
                        if !visible && selectedTab == .projects {
                            selectedTab = .home
                        }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await HealthSyncService.shared.performSyncIfNeeded(modelContext: modelContext)
                }
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
    var shouldShowProjectsTab: Bool {
        !(UIDevice.current.userInterfaceIdiom == .pad &&
          horizontalSizeClass == .regular &&
          UIScreen.main.bounds.width > UIScreen.main.bounds.height)
    }
}
