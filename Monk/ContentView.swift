//
//  ContentView.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager: FocusManager?
    @State private var selectedTab: AppTab = .home
    @StateObject private var tutorial = TutorialCoordinator()

    var body: some View {
        Group {
            if let manager = manager {
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
                .onAppear {
                    tutorial.tabSelectionHandler = { tab in
                        if selectedTab != tab {
                            selectedTab = tab
                        }
                    }
                }
                .onChange(of: tutorial.activeStage) { _, stage in
                    guard let stage, selectedTab != stage.preferredTab else { return }
                    selectedTab = stage.preferredTab
                }
            } else {
                ProgressView().task {
                    await MainActor.run { self.manager = FocusManager(modelContext: modelContext) }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
