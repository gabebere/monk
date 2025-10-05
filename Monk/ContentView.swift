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
    @State private var selectedTab: Tab = .home

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
                    .tag(Tab.home)

                    NavigationStack {
                        InsightsView()
                    }
                    .tabItem {
                        Label("", systemImage: "chart.bar.doc.horizontal")
                            .accessibilityLabel("Data")
                    }
                    .tag(Tab.data)

                    NavigationStack {
                        HistoryView()
                    }
                    .tabItem {
                        Label("", systemImage: "clock.arrow.circlepath")
                            .accessibilityLabel("History")
                    }
                    .tag(Tab.history)

                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label("", systemImage: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                    .tag(Tab.settings)
                }
                .preferredColorScheme(.dark)
                .tint(.white)
                .onChange(of: selectedTab) { _, _ in
                    Haptics.medium()
                    Haptics.soft()
                }
                .environmentObject(manager)
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

private enum Tab: Hashable {
    case home
    case data
    case history
    case settings
}
