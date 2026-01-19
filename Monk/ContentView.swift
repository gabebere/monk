//
//  ContentView.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import RevenueCat
import RevenueCatUI
import SwiftData
import SwiftUI
import Combine
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authManager = AuthManager()
    @StateObject private var revenueCat = RevenueCatService()
    @StateObject private var entitlementSync = EntitlementSyncService()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasCompletedSetupChecklist") private var hasCompletedSetupChecklist = false
    @State private var manager: FocusManager?
    @State private var selectedTab: AppTab = .home
    @State private var requirePaywall = false
    @State private var didSeedDemoData = false
    @State private var pendingOnboardingPaywall = false

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
                .environmentObject(revenueCat)
            } else if !hasSeenOnboarding {
                OnboardingStoryView { completion in
                    hasSeenOnboarding = true
                    if completion.requestPricing {
                        pendingOnboardingPaywall = true
                        if authManager.isAuthenticated && !revenueCat.isPro {
                            requirePaywall = true
                        }
                    }
                }
                .environmentObject(authManager)
                .environmentObject(revenueCat)
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
                            ProjectsTabView()
                        }
                        .tabItem {
                            Label("", systemImage: "square.grid.2x2")
                                .accessibilityLabel("Projects")
                        }
                        .tag(AppTab.projects)

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
                    .environmentObject(revenueCat)
                    .environmentObject(authManager)
                    .environmentObject(entitlementSync)
                    .onAppear {
                        updatePaywallRequirement()
                    }
                    .onChange(of: revenueCat.isPro) { _, _ in
                        entitlementSync.updateFromRevenueCat(isPro: revenueCat.isPro, userId: authManager.currentUserId)
                        updatePaywallRequirement()
                    }
                    .onChange(of: authManager.isAuthenticated) { _, _ in
                        updatePaywallRequirement()
                        Task {
                            if authManager.isAuthenticated, let userID = authManager.currentUserId {
                                await revenueCat.logIn(userId: userID)
                            } else {
                                await revenueCat.logOut()
                            }
                        }
                    }
                    .fullScreenCover(isPresented: $requirePaywall) {
                        RevenueCatPaywallView(onClose: {
                            requirePaywall = false
                        })
                            .environmentObject(revenueCat)
                            .interactiveDismissDisabled(!revenueCat.isPro)
                    }
                    .onOpenURL { url in
#if canImport(GoogleSignIn)
                        _ = GIDSignIn.sharedInstance.handle(url)
#endif
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
    }
}

#Preview {
    ContentView()
            .modelContainer(for: [
                FocusSession.self,
                Preferences.self,
                Project.self,
                FocusTask.self
            ], inMemory: true)
}

private extension ContentView {
    func updatePaywallRequirement() {
        if pendingOnboardingPaywall && authManager.isAuthenticated && !(revenueCat.isPro || entitlementSync.isEntitled) {
            pendingOnboardingPaywall = false
            requirePaywall = true
            return
        }
        if revenueCat.isPro {
            pendingOnboardingPaywall = false
        }
        requirePaywall = authManager.isAuthenticated && !(revenueCat.isPro || entitlementSync.isEntitled)
    }

    var calendarLoggingEnabledOnThisDevice: Bool {
        if let value = UserDefaults.standard.object(forKey: "calendar.logging.enabled") as? Bool {
            return value
        }
        return true
    }
}
