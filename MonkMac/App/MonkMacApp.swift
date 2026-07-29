import AppKit
import SwiftUI

@MainActor
final class MonkMacEnvironment {
    static let shared = MonkMacEnvironment()

    let catalog: ApplicationCatalog
    let guardian: WorkspaceApplicationGuardian
    let websiteGuardian: BrowserWebsiteGuardian
    let crossDeviceSync: CrossDeviceFocusSyncService
    let store: FocusSessionStore
    let panelController: CommandPanelController
    let hotKeyController: GlobalHotKeyController

    private init() {
        let catalog = ApplicationCatalog()
        let guardian = WorkspaceApplicationGuardian()
        let websiteGuardian = BrowserWebsiteGuardian()
        let crossDeviceSync = CrossDeviceFocusSyncService(applicationCatalog: catalog)
        let store = FocusSessionStore(
            guardian: guardian,
            websiteGuardian: websiteGuardian,
            syncService: crossDeviceSync,
            installedBrowserProvider: { catalog.supportedBrowsers }
        )

        let panelController = CommandPanelController(store: store, catalog: catalog)
        let hotKeyController = GlobalHotKeyController { [weak panelController] in
            panelController?.toggle()
        }

        self.catalog = catalog
        self.guardian = guardian
        self.websiteGuardian = websiteGuardian
        self.crossDeviceSync = crossDeviceSync
        self.store = store
        self.panelController = panelController
        self.hotKeyController = hotKeyController

        guardian.onBlockedApplication = { [weak store, weak panelController] name in
            store?.recordBlockedApplication(named: name)
            panelController?.show()
        }
        websiteGuardian.onBlockedWebsite = { [weak store, weak panelController] website in
            store?.recordBlockedWebsite(website)
            panelController?.show()
        }
        crossDeviceSync.onReceivedCommitment = { [weak store] commitment in
            let resolvedApplications = commitment.allowedApplications.compactMap { requestedApplication in
                catalog.applications.first {
                    requestedApplication.matches(
                        displayName: $0.displayName,
                        bundleIdentifier: $0.bundleIdentifier
                    )
                }
            }
            store?.startSyncedFocus(
                commitment,
                resolvedApplications: resolvedApplications
            )
        }
    }
}

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
            MonkMacSettingsView()
        }
    }
}

@MainActor
final class MonkMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        MonkMacEnvironment.shared.catalog.reload()
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
