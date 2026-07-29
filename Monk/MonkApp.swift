import SwiftUI
import UIKit

@main
struct MonkApp: App {
    @UIApplicationDelegateAdaptor(MonkAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class MonkAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit uses silent pushes. This does not ask for visible-notification permission.
        application.registerForRemoteNotifications()
        CrossDeviceFocusService.shared.start()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let changed = await CrossDeviceFocusService.shared.handleRemoteNotification(userInfo: userInfo)
            completionHandler(changed ? .newData : .noData)
        }
    }
}
