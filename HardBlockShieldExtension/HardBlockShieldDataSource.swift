import Foundation
import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import UIKit

private enum HardBlockShieldPalette {
    static let primaryText = UIColor(white: 0.98, alpha: 1)
    static let secondaryText = UIColor(white: 0.86, alpha: 1)
    static let buttonBackground = UIColor.systemIndigo
    static let buttonText = UIColor.white

    // Use a single solid color to avoid any memory churn in the extension.
    static let backgroundColor = UIColor(red: 0.12, green: 0.07, blue: 0.26, alpha: 1)

    static func emblemIcon() -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 48, weight: .semibold)
        return UIImage(systemName: "sparkles", withConfiguration: configuration)?.withTintColor(UIColor(white: 1.0, alpha: 0.9), renderingMode: .alwaysOriginal)
    }
}

private enum HardBlockShieldCopy {
    static func title(projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "Enjoy your focus on \(projectTitle)"
        }
        return "Enjoy your focus"
    }

    static func subtitle(appName: String, projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "Stay present; \(appName) is paused for \(projectTitle)."
        }
        return "Stay present; distractions are paused."
    }

    static func subtitle(domain: String, projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "Focus first; \(domain) is paused for \(projectTitle)."
        }
        return "Focus first; this site is paused."
    }

    static let primaryButton = "Back to Monk"
}

private struct HardBlockShieldState: Codable {
    let projectTitle: String?
    let selectionData: Data
    let activatedAt: Date

    func selection() -> FamilyActivitySelection? {
        try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
    }
}

private enum HardBlockShieldStore {
    private static let suiteName = "group.com.gbr.Monk"
    private static let fileName = "hardBlockState.json"
    private static var didBootstrap = false

    static func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        let fm = FileManager.default
        if let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            if !fm.fileExists(atPath: containerURL.path) {
                try? fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
            }
        }
    }

    private static func loadState() -> HardBlockShieldState? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else {
            return nil
        }
        let url = containerURL.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HardBlockShieldState.self, from: data)
    }

    static var projectTitle: String? {
        loadState()?.projectTitle
    }

    static var isActive: Bool {
        loadState() != nil
    }

    static func contains(application token: ManagedSettings.ApplicationToken?) -> Bool {
        guard let selection = loadState()?.selection() else { return false }

        if selection.includeEntireCategory {
            guard let token else { return true }
            return !selection.applicationTokens.contains(token)
        }

        if let token, selection.applicationTokens.contains(token) {
            return true
        }

        if !selection.categoryTokens.isEmpty {
            return true
        }

        return false
    }

    static func contains(category token: ManagedSettings.ActivityCategoryToken?) -> Bool {
        guard let token, let selection = loadState()?.selection() else { return false }
        if selection.includeEntireCategory { return true }
        return selection.categoryTokens.contains(token)
    }

    static func contains(webDomain token: ManagedSettings.WebDomainToken?) -> Bool {
        guard let token, let selection = loadState()?.selection() else { return false }
        return selection.webDomainTokens.contains(token)
    }
}

@objc final class HardBlockShieldUIExtension: ShieldConfigurationDataSource {
    override init() {
        HardBlockShieldStore.bootstrap()
        super.init()
    }

    override func configuration(shielding application: ManagedSettings.Application) -> ShieldConfiguration {
        let displayName = application.localizedDisplayName ?? "This app"
        return baseConfiguration(title: displayName)
    }

    override func configuration(shielding application: ManagedSettings.Application, in category: ManagedSettings.ActivityCategory) -> ShieldConfiguration {
        let displayName = application.localizedDisplayName ?? "This app"
        return baseConfiguration(title: displayName)
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain) -> ShieldConfiguration {
        let domain = webDomain.domain ?? "This site"
        return baseConfiguration(title: domain)
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain, in category: ManagedSettings.ActivityCategory) -> ShieldConfiguration {
        let domain = webDomain.domain ?? "This site"
        return baseConfiguration(title: domain)
    }
}

private extension HardBlockShieldUIExtension {
    func baseConfiguration(title: String) -> ShieldConfiguration {
        hardBlockConfiguration(title: title, subtitle: "")
    }

    func hardBlockConfiguration(title: String, subtitle: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: HardBlockShieldPalette.backgroundColor,
            icon: HardBlockShieldPalette.emblemIcon(),
            title: .init(text: "Enjoy your focus", color: HardBlockShieldPalette.primaryText),
            subtitle: .init(text: "", color: HardBlockShieldPalette.secondaryText),
            primaryButtonLabel: .init(text: HardBlockShieldCopy.primaryButton, color: HardBlockShieldPalette.buttonText),
            primaryButtonBackgroundColor: HardBlockShieldPalette.buttonBackground
        )
    }

    func placeholderConfiguration(title: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: HardBlockShieldPalette.backgroundColor,
            icon: HardBlockShieldPalette.emblemIcon(),
            title: .init(text: "Enjoy your focus", color: HardBlockShieldPalette.primaryText),
            subtitle: .init(text: "", color: HardBlockShieldPalette.secondaryText),
            primaryButtonLabel: .init(text: HardBlockShieldCopy.primaryButton, color: HardBlockShieldPalette.buttonText),
            primaryButtonBackgroundColor: HardBlockShieldPalette.buttonBackground
        )
    }
}
