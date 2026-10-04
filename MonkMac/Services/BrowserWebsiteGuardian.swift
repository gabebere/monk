import AppKit
import Foundation
import OSLog

@MainActor
protocol WebsiteGuarding: AnyObject {
    var onBlockedWebsite: ((String) -> Void)? { get set }
    func beginEnforcing(_ policy: FocusPolicy)
    func stopEnforcing()
}

@MainActor
final class BrowserWebsiteGuardian: WebsiteGuarding {
    var onBlockedWebsite: ((String) -> Void)?

    private let workspace = NSWorkspace.shared
    private let logger = Logger(subsystem: "com.gbr.Monk.mac", category: "WebsiteGuardian")
    private var navigationAllowance = WebsiteNavigationAllowance(domains: [])
    private var timer: Timer?

    func beginEnforcing(_ policy: FocusPolicy) {
        stopEnforcing()
        navigationAllowance = WebsiteNavigationAllowance(domains: policy.allowedDomains)

        inspectFrontmostBrowser()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.inspectFrontmostBrowser()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopEnforcing() {
        timer?.invalidate()
        timer = nil
    }

    private func inspectFrontmostBrowser() {
        guard let application = workspace.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleIdentifier = application.bundleIdentifier,
              let browser = ScriptableBrowser(bundleIdentifier: bundleIdentifier) else {
            return
        }

        switch browser.activeURL() {
        case let .success(rawURL):
            guard !rawURL.isEmpty else { return }

            if navigationAllowance.allows(
                rawURL,
                in: bundleIdentifier,
                at: .now
            ) {
                return
            }

            let host = WebsiteAllowlist.displayHost(for: rawURL)
            let replacementURL = blockedPageURL(for: host)
            switch browser.navigate(to: replacementURL) {
            case .success:
                logger.notice("Blocking website: \(host, privacy: .public)")
                onBlockedWebsite?(host)
            case let .failure(failure):
                blockBrowser(application, failure: failure)
            }

        case let .failure(failure):
            guard !failure.isTransient else { return }
            blockBrowser(application, failure: failure)
        }
    }

    private func blockBrowser(_ application: NSRunningApplication, failure: AppleScriptFailure) {
        let name = application.localizedName ?? "Browser"
        logger.error("Cannot inspect \(name, privacy: .public): \(failure.message, privacy: .public)")
        onBlockedWebsite?("\(name) — allow browser access")

        if !application.terminate() {
            _ = application.forceTerminate()
        }
        Task { @MainActor [weak application] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let application, !application.isTerminated else { return }
            _ = application.forceTerminate()
        }
    }

    private func blockedPageURL(for host: String) -> String {
        guard let pageURL = Bundle.main.url(forResource: "BlockedWebsite", withExtension: "html"),
              var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return "about:blank"
        }

        components.queryItems = [URLQueryItem(name: "site", value: host)]
        return components.url?.absoluteString ?? pageURL.absoluteString
    }
}

private struct AppleScriptFailure: Error {
    let number: Int
    let message: String

    var isTransient: Bool {
        // The browser closed, changed windows, or changed tabs while Monk queried it.
        [-600, -609, -1712, -1728].contains(number)
    }
}

enum SupportedBrowser {
    enum ScriptingFamily: Equatable {
        case safari
        case chromium
    }

    static func scriptingFamily(for bundleIdentifier: String) -> ScriptingFamily? {
        if bundleIdentifier == "com.apple.Safari" || bundleIdentifier.hasPrefix("com.apple.Safari.") {
            return .safari
        }
        if chromiumBundleIdentifiers.contains(bundleIdentifier) {
            return .chromium
        }
        return nil
    }

    static func canEnforceWebsites(in bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return scriptingFamily(for: bundleIdentifier) != nil
    }

    private static let chromiumBundleIdentifiers: Set<String> = [
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary",
        "com.microsoft.edgemac.Dev",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
        "company.thebrowser.Browser.beta",
        "org.chromium.Chromium"
    ]
}

private enum ScriptableBrowser {
    case safari(bundleIdentifier: String)
    case chromium(bundleIdentifier: String)

    init?(bundleIdentifier: String) {
        switch SupportedBrowser.scriptingFamily(for: bundleIdentifier) {
        case .safari:
            self = .safari(bundleIdentifier: bundleIdentifier)
        case .chromium:
            self = .chromium(bundleIdentifier: bundleIdentifier)
        case nil:
            return nil
        }
    }

    func activeURL() -> Result<String, AppleScriptFailure> {
        execute(body: activeURLBody)
    }

    func navigate(to rawURL: String) -> Result<String, AppleScriptFailure> {
        let escapedURL = rawURL
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return execute(body: "set URL of \(tabReference) to \"\(escapedURL)\"\nreturn \"\"")
    }

    private var bundleIdentifier: String {
        switch self {
        case let .safari(bundleIdentifier), let .chromium(bundleIdentifier):
            bundleIdentifier
        }
    }

    private var tabReference: String {
        switch self {
        case .safari:
            "current tab of front window"
        case .chromium:
            "active tab of front window"
        }
    }

    private var activeURLBody: String {
        "if (count of windows) is 0 then return \"\"\nreturn URL of \(tabReference)"
    }

    private func execute(body: String) -> Result<String, AppleScriptFailure> {
        let source = """
        tell application id "\(bundleIdentifier)"
            if not running then return ""
            \(body)
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            return .failure(AppleScriptFailure(number: -1, message: "Could not create browser script"))
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo["NSAppleScriptErrorNumber"] as? Int ?? -1
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String ?? "Unknown browser automation error"
            return .failure(AppleScriptFailure(number: number, message: message))
        }
        return .success(result.stringValue ?? "")
    }

}
