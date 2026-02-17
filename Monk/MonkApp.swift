//
//  MonkApp.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import OSLog
import SwiftData
import SwiftUI
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(UserJot)
import UserJot
#endif

@main
struct MonkApp: App {
    @UIApplicationDelegateAdaptor(MonkAppDelegate.self) private var appDelegate

    init() {
        HardBlockStateStore.bootstrap()
        Analytics.configure()
#if canImport(UserJot)
        UserJot.setup(projectId: "cmiptfvv400yb15lbz1dzqbey")
#endif
        MirrorSyncService.shared.setModelContainer(sharedModelContainer)
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
        let logger = Logger(subsystem: "com.gbr.Monk", category: "Persistence")
        let schema = Schema([
            FocusSession.self,
            Preferences.self,
            Project.self,
            FocusTask.self,
            HealthSampleLink.self
        ])
        do {
            let configuration = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.gbr.Monk")
             )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("Failed to create CloudKit-backed ModelContainer: \(error.localizedDescription, privacy: .public)")
            let fallbackConfiguration = ModelConfiguration(isStoredInMemoryOnly: false)
            do {
                logger.info("Falling back to on-device ModelContainer storage.")
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                logger.critical("Failed to create fallback ModelContainer: \(error.localizedDescription, privacy: .public)")
                fatalError("Unable to create ModelContainer: \(error)")
            }
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
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "AppDelegate")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        let preview = token.prefix(12)
        logger.debug("Registered for remote notifications. Token preview: \(preview, privacy: .public)")
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
#if canImport(GoogleSignIn)
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
#endif
        return false
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await MirrorSyncService.shared.handleRemoteNotification(userInfo: userInfo)
            completionHandler(.newData)
        }
    }
}
