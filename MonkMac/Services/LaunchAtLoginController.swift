import Foundation
import OSLog
import ServiceManagement

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
}

extension SMAppService: LaunchAtLoginServicing {}

@MainActor
final class LaunchAtLoginController {
    static let configurationKey = "launchAtLogin.hasConfigured"

    private let service: LaunchAtLoginServicing
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.gbr.Monk.mac", category: "LaunchAtLogin")

    init(
        service: LaunchAtLoginServicing = SMAppService.mainApp,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
    }

    func registerIfNeeded() {
        switch service.status {
        case .enabled:
            defaults.set(true, forKey: Self.configurationKey)

        case .requiresApproval:
            defaults.set(true, forKey: Self.configurationKey)
            logger.notice("Launch at login requires approval in System Settings")

        case .notRegistered:
            registerOnce()

        case .notFound:
            // A freshly installed development build can briefly report notFound
            // before Launch Services finishes indexing its stable bundle path.
            registerOnce()

        @unknown default:
            logger.error("Unable to determine launch-at-login status")
        }
    }

    private func registerOnce() {
        guard defaults.object(forKey: Self.configurationKey) == nil else {
            return
        }

        do {
            try service.register()
            defaults.set(true, forKey: Self.configurationKey)
            logger.notice("Enabled launch at login")
        } catch {
            logger.error("Unable to enable launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
