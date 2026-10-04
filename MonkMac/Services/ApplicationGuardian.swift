import AppKit
import Foundation
import OSLog

@MainActor
protocol ApplicationGuarding: AnyObject {
    var onBlockedApplication: ((String) -> Void)? { get set }
    func beginEnforcing(
        _ policy: FocusPolicy,
        alwaysAllowing applications: [ApplicationDescriptor]
    )
    func beginDefaultBlocking(allowing applications: [ApplicationDescriptor])
    func stopEnforcing()
}

@MainActor
final class WorkspaceApplicationGuardian: ApplicationGuarding {
    var onBlockedApplication: ((String) -> Void)?

    private let workspace = NSWorkspace.shared
    private let logger = Logger(subsystem: "com.gbr.Monk.mac", category: "ApplicationGuardian")
    private var allowedApplicationIDs: Set<String>?
    private var allowsSupportedBrowsers = false
    private var observers: [NSObjectProtocol] = []

    private var permanentlyAllowedApplicationIDs: Set<String> {
        var identifiers: Set<String> = [
            "com.apple.finder",
            "com.apple.systempreferences",
            "com.apple.SystemSettings"
        ]
        if let monkIdentifier = Bundle.main.bundleIdentifier {
            identifiers.insert(monkIdentifier)
        }
        return identifiers
    }

    func beginEnforcing(
        _ policy: FocusPolicy,
        alwaysAllowing applications: [ApplicationDescriptor]
    ) {
        allowedApplicationIDs = policy.allowedApplicationIDs.union(applications.map(\.id))
        allowsSupportedBrowsers = !policy.allowedDomains.isEmpty
        beginEnforcingRunningApplications()
    }

    func beginDefaultBlocking(allowing applications: [ApplicationDescriptor]) {
        allowedApplicationIDs = Set(applications.map(\.id))
        allowsSupportedBrowsers = false
        beginEnforcingRunningApplications()
    }

    private func beginEnforcingRunningApplications() {
        installObserversIfNeeded()

        for application in workspace.runningApplications {
            enforce(application, wasRunningAtSessionStart: true)
        }
    }

    func stopEnforcing() {
        allowedApplicationIDs = nil
        allowsSupportedBrowsers = false
        observers.forEach(workspace.notificationCenter.removeObserver)
        observers.removeAll()
    }

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }

        let launched = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.enforce(application, wasRunningAtSessionStart: false)
            }
        }

        let activated = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.enforce(application, wasRunningAtSessionStart: false)
            }
        }

        observers = [launched, activated]
    }

    private func enforce(_ application: NSRunningApplication, wasRunningAtSessionStart: Bool) {
        guard allowedApplicationIDs != nil,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular,
              shouldBlock(application) else {
            return
        }

        let name = application.localizedName ?? "Blocked application"
        logger.notice("Blocking application: \(name, privacy: .public)")
        onBlockedApplication?(name)

        if wasRunningAtSessionStart {
            // Preserve unsaved work: an existing app receives a normal Quit request.
            _ = application.terminate()
        } else {
            // A newly launched blocked app should not remain available long enough to use.
            if !application.terminate() {
                _ = application.forceTerminate()
            }
            Task { @MainActor [weak application] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let application, !application.isTerminated else { return }
                _ = application.forceTerminate()
            }
        }
    }

    private func shouldBlock(_ application: NSRunningApplication) -> Bool {
        let applicationID = application.bundleIdentifier ?? application.bundleURL?.standardizedFileURL.path
        guard let applicationID else { return true }
        guard !permanentlyAllowedApplicationIDs.contains(applicationID) else { return false }
        if allowsSupportedBrowsers,
           SupportedBrowser.canEnforceWebsites(in: application.bundleIdentifier) {
            return false
        }
        return !(allowedApplicationIDs?.contains(applicationID) ?? false)
    }
}
