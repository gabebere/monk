import AppKit
import SwiftUI

@main
struct MonkMacApp: App {
    @NSApplicationDelegateAdaptor(MonkMacAppDelegate.self) private var appDelegate
    @StateObject private var store = MonkMacEnvironment.shared.store

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: store,
                showCommandPanel: MonkMacEnvironment.shared.panelController.show
            )
        } label: {
            Image(systemName: store.activePolicy == nil ? "circle.hexagongrid" : "circle.hexagongrid.fill")
        }

        Settings {
            MonkMacSettingsView(
                store: MonkMacEnvironment.shared.store,
                catalog: MonkMacEnvironment.shared.catalog,
                calendarRecorder: MonkMacEnvironment.shared.calendarRecorder
            )
        }
    }
}

@MainActor
final class MonkMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        MonkMacEnvironment.shared.catalog.reload()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            MonkMacEnvironment.shared.launchAtLoginController.registerIfNeeded()
        }
        MonkMacEnvironment.shared.hotKeyController.register()
        MonkMacEnvironment.shared.store.restorePersistedSessionIfNeeded()
        MonkMacEnvironment.shared.crossDeviceSync.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MonkMacEnvironment.shared.panelController.show()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !MonkMacEnvironment.shared.store.preventsTermination else {
            MonkMacEnvironment.shared.panelController.show()
            return .terminateCancel
        }

        return .terminateNow
    }
}
