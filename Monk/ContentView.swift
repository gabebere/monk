//
//  ContentView.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import MonkShared
import RevenueCat
import RevenueCatUI
import SwiftData
import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authManager = AuthManager()
    @StateObject private var revenueCat = RevenueCatService()
    @StateObject private var entitlementSync = EntitlementSyncService()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("shouldShowSetupChecklist") private var shouldShowSetupChecklist = false
    @AppStorage("hasCompletedSetupChecklist") private var hasCompletedSetupChecklist = false
    @AppStorage("hasPresentedOnboardingPaywall") private var hasPresentedOnboardingPaywall = false
    @State private var manager: FocusManager?
    @State private var liveSessionSync: LiveSessionSyncService?
    @State private var selectedTab: AppTab = .home
    @State private var requirePaywall = false
    @State private var didSeedDemoData = false
    @State private var pendingOnboardingPaywall = false

    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                AuthGatewayView()
                    .environmentObject(authManager)
            } else if !hasSeenOnboarding {
                OnboardingStoryView { completion in
                    hasSeenOnboarding = true
                    if completion.requestPricing {
                        if authManager.isAuthenticated {
                            if revenueCat.isPro || entitlementSync.isEntitled {
                                if !hasCompletedSetupChecklist {
                                    shouldShowSetupChecklist = true
                                }
                            } else {
                                if !hasPresentedOnboardingPaywall {
                                    requirePaywall = true
                                    hasPresentedOnboardingPaywall = true
                                }
                            }
                        }
                    } else if authManager.isAuthenticated && (revenueCat.isPro || entitlementSync.isEntitled) {
                        // Already entitled users should still see the setup checklist after onboarding.
                        if !hasCompletedSetupChecklist {
                            shouldShowSetupChecklist = true
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
                    .environmentObject(revenueCat)
                    .environmentObject(authManager)
                    .environmentObject(entitlementSync)
                    .onAppear {
                        updatePaywallRequirement()
                    }
                    .onChange(of: revenueCat.isPro) { _, _ in
                        entitlementSync.updateFromRevenueCat(isPro: revenueCat.isPro, userId: authManager.currentUserId)
                        updatePaywallRequirement()
                        if revenueCat.isPro && !hasCompletedSetupChecklist {
                            shouldShowSetupChecklist = true
                        }
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
                            if !hasCompletedSetupChecklist {
                                shouldShowSetupChecklist = true
                            }
                        })
                            .environmentObject(revenueCat)
                            .interactiveDismissDisabled(!revenueCat.isPro)
                    }
                    .fullScreenCover(isPresented: $shouldShowSetupChecklist) {
                        SetupChecklistView {
                            shouldShowSetupChecklist = false
                            hasCompletedSetupChecklist = true
                        }
                        .environmentObject(authManager)
                        .environmentObject(revenueCat)
                        .environmentObject(entitlementSync)
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
                        if liveSessionSync == nil {
                            liveSessionSync = LiveSessionSyncService(modelContext: modelContext)
                            print("[LiveSessionSync] created in ContentView task")
                        }
                        await MainActor.run {
                            self.manager = FocusManager(modelContext: modelContext, liveSessionSync: liveSessionSync)
                        }
                        await DailyFocusNotificationScheduler.scheduleDailySummary(modelContext: modelContext)
                    }
                } else {
                    ProgressView()
                        .task {
                            await MainActor.run {
                                if liveSessionSync == nil {
                                    liveSessionSync = LiveSessionSyncService(modelContext: modelContext)
                                    print("[LiveSessionSync] created in ProgressView task")
                                }
                                self.manager = FocusManager(modelContext: modelContext, liveSessionSync: liveSessionSync)
                            }
                    }
                }
            } else {
                AuthGatewayView()
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            if hasCompletedSetupChecklist {
                shouldShowSetupChecklist = false
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
    func updatePaywallRequirement() {
        // Only clear a pending paywall when the user becomes entitled; never force-present here.
        if revenueCat.isPro || entitlementSync.isEntitled {
            requirePaywall = false
        }
    }
}
