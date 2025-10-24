import Foundation
import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import UIKit

private enum HardBlockShieldPalette {
    static let gradientStart = UIColor(red: 32 / 255, green: 24 / 255, blue: 68 / 255, alpha: 1)
    static let gradientEnd = UIColor(red: 10 / 255, green: 56 / 255, blue: 120 / 255, alpha: 1)
    static let primaryText = UIColor(white: 0.98, alpha: 1)
    static let secondaryText = UIColor(white: 0.88, alpha: 0.82)
    static let buttonBackground = UIColor(red: 248 / 255, green: 113 / 255, blue: 62 / 255, alpha: 1)
    static let buttonText = UIColor.white
    static let secondaryButtonText = UIColor(white: 0.95, alpha: 0.85)

    static func gradientBackground() -> UIColor {
        let size = CGSize(width: 1, height: 512)
        UIGraphicsBeginImageContextWithOptions(size, true, 0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return gradientStart }
        let colors = [gradientStart.cgColor, gradientEnd.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else {
            return gradientStart
        }
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: size.height),
                                   options: [])
        if let image = UIGraphicsGetImageFromCurrentImageContext() {
            return UIColor(patternImage: image)
        }
        return gradientStart
    }

    static func emblemIcon() -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 72, weight: .semibold)
        return UIImage(systemName: "brain.head.profile", withConfiguration: configuration)?.withTintColor(UIColor(white: 1.0, alpha: 0.9), renderingMode: .alwaysOriginal)
    }
}

private enum HardBlockShieldCopy {
    static func title(projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "Deep focus for \(projectTitle)"
        }
        return "Eyes on your focus"
    }

    static func subtitle(appName: String, projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "\(appName) is resting while you power through \(projectTitle)."
        }
        return "\(appName) returns when your current focus session wraps up."
    }

    static func subtitle(domain: String, projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "Stay with \(projectTitle) for now—\(domain) will wait."
        }
        return "\(domain) is paused until this focus session ends."
    }

    static let primaryButton = "Back to focus"
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
        if HardBlockShieldStore.contains(application: application.token) || HardBlockShieldStore.isActive {
            return hardBlockConfiguration(title: displayName, subtitle: HardBlockShieldCopy.subtitle(appName: displayName, projectTitle: HardBlockShieldStore.projectTitle))
        }
        return placeholderConfiguration(title: displayName)
    }

    override func configuration(shielding application: ManagedSettings.Application, in category: ManagedSettings.ActivityCategory) -> ShieldConfiguration {
        if HardBlockShieldStore.contains(category: category.token) || HardBlockShieldStore.isActive {
            let displayName = application.localizedDisplayName ?? "This app"
            return hardBlockConfiguration(title: displayName, subtitle: HardBlockShieldCopy.subtitle(appName: displayName, projectTitle: HardBlockShieldStore.projectTitle))
        }
        return configuration(shielding: application)
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain) -> ShieldConfiguration {
        let domain = webDomain.domain ?? "This site"
        if HardBlockShieldStore.contains(webDomain: webDomain.token) || HardBlockShieldStore.isActive {
            return hardBlockConfiguration(title: domain, subtitle: HardBlockShieldCopy.subtitle(domain: domain, projectTitle: HardBlockShieldStore.projectTitle))
        }
        return placeholderConfiguration(title: domain)
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain, in category: ManagedSettings.ActivityCategory) -> ShieldConfiguration {
        if HardBlockShieldStore.contains(category: category.token) || HardBlockShieldStore.contains(webDomain: webDomain.token) || HardBlockShieldStore.isActive {
            let domain = webDomain.domain ?? "This site"
            return hardBlockConfiguration(title: domain, subtitle: HardBlockShieldCopy.subtitle(domain: domain, projectTitle: HardBlockShieldStore.projectTitle))
        }
        return configuration(shielding: webDomain)
    }
}

private extension HardBlockShieldUIExtension {
    func hardBlockConfiguration(title: String, subtitle: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: HardBlockShieldPalette.gradientBackground(),
            icon: HardBlockShieldPalette.emblemIcon(),
            title: .init(text: HardBlockShieldCopy.title(projectTitle: HardBlockShieldStore.projectTitle), color: HardBlockShieldPalette.primaryText),
            subtitle: .init(text: subtitle, color: HardBlockShieldPalette.secondaryText),
            primaryButtonLabel: .init(text: HardBlockShieldCopy.primaryButton, color: HardBlockShieldPalette.buttonText),
            primaryButtonBackgroundColor: HardBlockShieldPalette.buttonBackground
        )
    }

    func placeholderConfiguration(title: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: HardBlockShieldPalette.gradientBackground(),
            icon: HardBlockShieldPalette.emblemIcon(),
            title: .init(text: "You’re in focus mode", color: HardBlockShieldPalette.primaryText),
            subtitle: .init(text: "\(title) is currently unavailable while Monk keeps distractions away.", color: HardBlockShieldPalette.secondaryText),
            primaryButtonLabel: .init(text: HardBlockShieldCopy.primaryButton, color: HardBlockShieldPalette.buttonText),
            primaryButtonBackgroundColor: HardBlockShieldPalette.buttonBackground
        )
    }
}
