//
//  MonkApp.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import SwiftUI
import UIKit
import SwiftData

@main
struct MonkApp: App {
    init() {
        // Global UINavigationBar appearance: white titles and buttons, transparent background
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
    }
    // Configure SwiftData model container for app-wide use
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FocusSession.self,
            Preferences.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
