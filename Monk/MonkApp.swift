//
//  MonkApp.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct MonkApp: App {
    @UIApplicationDelegateAdaptor(MonkAppDelegate.self) private var appDelegate

    init() {
        HardBlockStateStore.bootstrap()
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
            Preferences.self,
            Project.self
        ])
        do {
            let configuration = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.gbr.Monk")
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            assertionFailure("Failed to create ModelContainer: \(error.localizedDescription)")
            let fallback = ModelConfiguration(isStoredInMemoryOnly: false)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

final class MonkAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("Registered for remote notifications with token: \(token)")
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}
