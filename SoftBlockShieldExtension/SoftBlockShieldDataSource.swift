import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

private enum SoftBlockShieldStrings {
    static func headline(for appName: String) -> String {
        "\(appName) can wait"
    }

    static let focusReminder = "Breathe. Monk is quietly holding distractions while you stay in flow."

    static func quickUnlockDetail(wait: TimeInterval, duration: TimeInterval) -> String {
        let waitString = formatted(seconds: Int(wait))
        let durationString = formatted(seconds: Int(duration))
        return "Need a quick peek? Pause for \(waitString) and enjoy \(durationString) of access."
    }

    static func waitingSubtitle(remaining: Int) -> String {
        "Almost there — unlock begins in \(formatted(seconds: remaining))."
    }

    static func unlockedSubtitle(remaining: Int) -> String {
        remaining > 0
            ? "Enjoy your mini break — \(formatted(seconds: remaining)) left."
            : "Monk is about to wrap this break."
    }

    private static func formatted(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) second\(seconds == 1 ? "" : "s")" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        return "\(minutes)m \(remainder)s"
    }
}

private enum SoftBlockShieldDurations {
    // Keep these values in sync with SoftBlockShieldActionExtension.
    static let wait: TimeInterval = 20
    static let unlock: TimeInterval = 120
}

private enum SoftBlockShieldPalette {
    static let background = UIColor(red: 28 / 255, green: 33 / 255, blue: 55 / 255, alpha: 0.94)
    static let surface = UIColor(red: 57 / 255, green: 71 / 255, blue: 110 / 255, alpha: 0.95)
    static let primaryButtonBackground = UIColor(red: 126 / 255, green: 199 / 255, blue: 255 / 255, alpha: 1.0)
    static let primaryButtonText = UIColor(red: 5 / 255, green: 16 / 255, blue: 32 / 255, alpha: 0.95)
    static let secondaryButtonText = UIColor(red: 146 / 255, green: 219 / 255, blue: 255 / 255, alpha: 1.0)
    static let textPrimary = UIColor(white: 0.96, alpha: 1.0)
    static let textSecondary = UIColor(white: 0.8, alpha: 1.0)
}

private enum HardBlockShieldPalette {
    static let background = UIColor(red: 8 / 255, green: 10 / 255, blue: 20 / 255, alpha: 0.96)
    static let surface = UIColor(red: 30 / 255, green: 33 / 255, blue: 50 / 255, alpha: 0.98)
    static let buttonBackground = UIColor(red: 88 / 255, green: 108 / 255, blue: 227 / 255, alpha: 1.0)
    static let buttonText = UIColor(white: 0.98, alpha: 1.0)
    static let textPrimary = UIColor(white: 0.95, alpha: 1.0)
    static let textSecondary = UIColor(white: 0.78, alpha: 1.0)
}

private enum HardBlockShieldStrings {
    static func headline(appName: String, projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "\(projectTitle) focus in progress"
        }
        return "Deep focus in progress"
    }

    static func subtitle(appName: String, projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "\(appName) will reopen once \"\(projectTitle)\" focus wraps."
        }
        return "\(appName) opens again when this focus session ends."
    }

    static func webSubtitle(domain: String, projectTitle: String?) -> String {
        if let projectTitle, !projectTitle.isEmpty {
            return "\(domain) is unavailable while you focus on \(projectTitle)."
        }
        return "\(domain) is unavailable while Monk keeps you focused."
    }

    static let primaryLabel = "Back to focus"
}

private extension ShieldConfiguration.Label {
    static func title(_ text: String) -> ShieldConfiguration.Label {
        .init(text: text, color: SoftBlockShieldPalette.textPrimary)
    }

    static func body(_ text: String) -> ShieldConfiguration.Label {
        .init(text: text, color: SoftBlockShieldPalette.textSecondary)
    }

    static func hardTitle(_ text: String) -> ShieldConfiguration.Label {
        .init(text: text, color: HardBlockShieldPalette.textPrimary)
    }

    static func hardBody(_ text: String) -> ShieldConfiguration.Label {
        .init(text: text, color: HardBlockShieldPalette.textSecondary)
    }
}

@objc final class SoftBlockShieldUIExtension: ShieldConfigurationDataSource {
    override init() {
        SoftBlockUnlockStore.bootstrap()
        HardBlockStateStore.bootstrap()
        super.init()
    }

    override func configuration(shielding application: ManagedSettings.Application) -> ShieldConfiguration {
        SoftBlockUnlockStore.clearExpired()
        let displayName = application.localizedDisplayName ?? "This app"
        if HardBlockStateStore.contains(application: application.token) || HardBlockStateStore.isActive {
            return hardBlockConfiguration(appName: displayName)
        }

        if let token = application.token, let record = SoftBlockUnlockStore.record(for: token) {
            return configuration(for: record, appName: displayName)
        }
        return promptConfiguration(appName: displayName)
    }

    override func configuration(shielding application: ManagedSettings.Application, in category: ManagedSettings.ActivityCategory) -> ShieldConfiguration {
        if HardBlockStateStore.contains(category: category.token) {
            return hardBlockConfiguration(appName: application.localizedDisplayName ?? "This app")
        }
        return configuration(shielding: application)
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain) -> ShieldConfiguration {
        if HardBlockStateStore.contains(webDomain: webDomain.token) || HardBlockStateStore.isActive {
            return hardBlockWebConfiguration(domain: webDomain.domain ?? "This site")
        }
        return baseConfiguration(
            title: "\(webDomain.domain ?? "This site") can wait",
            subtitle: "Monk is keeping this site quiet while you focus.",
            primaryLabel: "Back to focus"
        )
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain, in category: ManagedSettings.ActivityCategory) -> ShieldConfiguration {
        if HardBlockStateStore.contains(category: category.token) || HardBlockStateStore.contains(webDomain: webDomain.token) || HardBlockStateStore.isActive {
            return hardBlockWebConfiguration(domain: webDomain.domain ?? "This site")
        }
        return configuration(shielding: webDomain)
    }

    private func promptConfiguration(appName: String) -> ShieldConfiguration {
        var subtitleLines: [String] = [SoftBlockShieldStrings.focusReminder]
        subtitleLines.append(
            SoftBlockShieldStrings.quickUnlockDetail(
                wait: SoftBlockShieldDurations.wait,
                duration: SoftBlockShieldDurations.unlock
            )
        )
        return baseConfiguration(
            title: SoftBlockShieldStrings.headline(for: appName),
            subtitle: subtitleLines.joined(separator: "\n"),
            primaryLabel: "Unlock for 3 min",
            secondaryLabel: "Back to focus"
        )
    }

    private func configuration(for record: SoftBlockUnlockRecord, appName: String) -> ShieldConfiguration {
        switch record.phase() {
        case .waiting(let remaining):
            return waitingConfiguration(appName: appName, remaining: remaining)
        case .unlocked(let remaining):
            return unlockedConfiguration(appName: appName, remaining: remaining)
        case .expired:
            SoftBlockUnlockStore.remove(id: record.id)
            return promptConfiguration(appName: appName)
        }
    }

    private func waitingConfiguration(appName: String, remaining: Int) -> ShieldConfiguration {
        return baseConfiguration(
            title: SoftBlockShieldStrings.headline(for: appName),
            subtitle: SoftBlockShieldStrings.waitingSubtitle(remaining: remaining),
            primaryLabel: "Never mind"
        )
    }

    private func unlockedConfiguration(appName: String, remaining: Int) -> ShieldConfiguration {
        return baseConfiguration(
            title: SoftBlockShieldStrings.headline(for: appName),
            subtitle: SoftBlockShieldStrings.unlockedSubtitle(remaining: remaining),
            primaryLabel: "Wrap it up"
        )
    }

    private func hardBlockConfiguration(appName: String) -> ShieldConfiguration {
        let projectTitle = HardBlockStateStore.projectTitle
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: HardBlockShieldPalette.background,
            icon: nil,
            title: .hardTitle(HardBlockShieldStrings.headline(appName: appName, projectTitle: projectTitle)),
            subtitle: .hardBody(HardBlockShieldStrings.subtitle(appName: appName, projectTitle: projectTitle)),
            primaryButtonLabel: .init(text: HardBlockShieldStrings.primaryLabel, color: HardBlockShieldPalette.buttonText),
            primaryButtonBackgroundColor: HardBlockShieldPalette.buttonBackground,
            secondaryButtonLabel: nil
        )
    }

    private func hardBlockWebConfiguration(domain: String) -> ShieldConfiguration {
        let projectTitle = HardBlockStateStore.projectTitle
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: HardBlockShieldPalette.background,
            icon: nil,
            title: .hardTitle(HardBlockShieldStrings.headline(appName: domain, projectTitle: projectTitle)),
            subtitle: .hardBody(HardBlockShieldStrings.webSubtitle(domain: domain, projectTitle: projectTitle)),
            primaryButtonLabel: .init(text: HardBlockShieldStrings.primaryLabel, color: HardBlockShieldPalette.buttonText),
            primaryButtonBackgroundColor: HardBlockShieldPalette.buttonBackground,
            secondaryButtonLabel: nil
        )
    }

    private func baseConfiguration(
        title: String,
        subtitle: String,
        primaryLabel: String,
        secondaryLabel: String? = nil
    ) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: SoftBlockShieldPalette.background,
            icon: nil,
            title: .title(title),
            subtitle: .body(subtitle),
            primaryButtonLabel: .init(text: primaryLabel, color: SoftBlockShieldPalette.primaryButtonText),
            primaryButtonBackgroundColor: SoftBlockShieldPalette.primaryButtonBackground,
            secondaryButtonLabel: secondaryLabel.map { .init(text: $0, color: SoftBlockShieldPalette.secondaryButtonText) }
        )
    }
}
