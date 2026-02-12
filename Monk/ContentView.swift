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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authManager = AuthManager()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasCompletedSetupChecklist") private var hasCompletedSetupChecklist = false
    @State private var manager: FocusManager?
    @State private var selectedTab: AppTab = .home
    @State private var didSeedDemoData = false
    @State private var unlockMessage: String?

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
                        if GIDSignIn.sharedInstance.handle(url) { return }
#endif
                        handleDeepLink(url)
                    }
                    .task {
                        if !didSeedDemoData {
                            didSeedDemoData = true
                            DemoDataSeeder.seedIfNeeded(modelContext: modelContext)
                        }
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
        .alert("Intent Unlock", isPresented: Binding(
            get: { unlockMessage != nil },
            set: { if !$0 { unlockMessage = nil } }
        )) {
            Button("OK", role: .cancel) { unlockMessage = nil }
        } message: {
            if let unlockMessage { Text(unlockMessage) }
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
    var calendarLoggingEnabledOnThisDevice: Bool {
        if let value = UserDefaults.standard.object(forKey: "calendar.logging.enabled") as? Bool {
            return value
        }
        return true
    }

    var shouldShowProjectsTab: Bool {
        !(UIDevice.current.userInterfaceIdiom == .pad &&
          horizontalSizeClass == .regular &&
          UIScreen.main.bounds.width > UIScreen.main.bounds.height)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "monk" else { return }
        switch url.host {
        case "quickunlock":
            if let shortcutURL = URL(string: "shortcuts://run-shortcut?name=Monk%20Unlock"),
               UIApplication.shared.canOpenURL(shortcutURL) {
                UIApplication.shared.open(shortcutURL, options: [:], completionHandler: nil)
            } else {
                selectedTab = .settings
                unlockMessage = "Shortcut not installed. Open Settings → Intent Mode to unlock manually."
            }
        case "unlock":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let query = components.queryItems?.first(where: { $0.name == "query" })?.value,
                  let minutesString = components.queryItems?.first(where: { $0.name == "minutes" })?.value,
                  let minutes = Int(minutesString) else {
                unlockMessage = "Invalid unlock link."
                return
            }
            Task { @MainActor in
                let result = await IntentBlockManager.shared.registerTemporaryUnlock(query: query,
                                                                                      minutes: minutes,
                                                                                      source: .shortcut,
                                                                                      modelContext: modelContext)
                switch result {
                case .unlocked(_, let entry):
                    unlockMessage = "Unlocked \(entry.displayName) for \(minutes) minute\(minutes == 1 ? "" : "s")."
                case .ambiguous:
                    unlockMessage = "More typing needed—unlock was ambiguous."
                case .noMatch:
                    unlockMessage = "No matching app for \"\(query)\"."
                case .authorizationDenied:
                    unlockMessage = "Screen Time authorization required."
                case .invalidMinutes:
                    unlockMessage = "Duration must be between 2 and 60 minutes."
                }
            }
        default:
            break
        }
    }
}
