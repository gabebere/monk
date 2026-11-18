import Foundation

@MainActor
final class MonkMacEnvironment {
    static let shared = MonkMacEnvironment()

    let calendarRecorder: CalendarFocusRecorder
    let catalog: ApplicationCatalog
    let crossDeviceSync: CrossDeviceFocusSyncService
    let guardian: WorkspaceApplicationGuardian
    let hotKeyController: GlobalHotKeyController
    let launchAtLoginController: LaunchAtLoginController
    let panelController: CommandPanelController
    let store: FocusSessionStore
    let websiteGuardian: BrowserWebsiteGuardian

    private init() {
        let catalog = ApplicationCatalog()
        let guardian = WorkspaceApplicationGuardian()
        let websiteGuardian = BrowserWebsiteGuardian()
        let crossDeviceSync = CrossDeviceFocusSyncService(applicationCatalog: catalog)
        let calendarRecorder = CalendarFocusRecorder()
        let store = FocusSessionStore(
            guardian: guardian,
            websiteGuardian: websiteGuardian,
            syncService: crossDeviceSync,
            calendarRecorder: calendarRecorder,
            installedBrowserProvider: { catalog.supportedBrowsers }
        )
        let panelController = CommandPanelController(store: store, catalog: catalog)
        let hotKeyController = GlobalHotKeyController { [weak panelController] in
            panelController?.toggle()
        }

        self.calendarRecorder = calendarRecorder
        self.catalog = catalog
        self.crossDeviceSync = crossDeviceSync
        self.guardian = guardian
        self.hotKeyController = hotKeyController
        self.launchAtLoginController = LaunchAtLoginController()
        self.panelController = panelController
        self.store = store
        self.websiteGuardian = websiteGuardian

        connectEnforcementCallbacks()
        connectSyncCallbacks()
    }

    private func connectEnforcementCallbacks() {
        guardian.onBlockedApplication = { [weak store, weak panelController] name in
            store?.recordBlockedApplication(named: name)
            panelController?.show()
        }
        websiteGuardian.onBlockedWebsite = { [weak store, weak panelController] website in
            store?.recordBlockedWebsite(website)
            panelController?.show()
        }
        store.onSessionAwaitingDecision = { [weak panelController] in
            panelController?.show()
        }
    }

    private func connectSyncCallbacks() {
        crossDeviceSync.onReceivedCommitment = { [weak store, weak catalog] commitment in
            let resolvedApplications = commitment.allowedApplications.compactMap {
                requestedApplication in
                requestedApplication.uniqueMatch(
                    in: catalog?.applications ?? [],
                    displayName: { $0.displayName },
                    bundleIdentifier: { $0.bundleIdentifier }
                )
            }
            store?.startSyncedFocus(
                commitment,
                resolvedApplications: resolvedApplications
            )
        }
        crossDeviceSync.onReceivedDefaultAccess = { [weak store, weak catalog] configuration in
            let resolvedApplications = configuration.applicationsAreAuthoritative
                ? configuration.applications.map {
                requestedApplication in
                    requestedApplication.uniqueMatch(
                        in: catalog?.applications ?? [],
                        displayName: { $0.displayName },
                        bundleIdentifier: { $0.bundleIdentifier }
                    ) ?? ApplicationDescriptor(mobileApplication: requestedApplication)
                }
                : store?.alwaysAllowedApplications ?? []
            store?.applySyncedDefaultBlocking(
                enabled: configuration.enabled,
                alwaysAllowedApplications: resolvedApplications
            )
        }
    }
}
