import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

private enum SoftBlockShieldStrings {
    static func headline(for appName: String) -> String {
        "\(appName) is softblocked"
    }

    static let focusReminder = "Monk is shielding distracting apps so you can stay in deep focus."

    static func quickUnlockDetail(wait: TimeInterval, duration: TimeInterval) -> String {
        let waitString = formatted(seconds: Int(wait))
        let durationString = formatted(seconds: Int(duration))
        return "Need a quick look? We can unlock after a \(waitString) pause for \(durationString)."
    }

    static func waitingSubtitle(remaining: Int) -> String {
        "Hang tight — unlock starts in \(formatted(seconds: remaining))."
    }

    static func unlockedSubtitle(remaining: Int) -> String {
        remaining > 0
            ? "You have \(formatted(seconds: remaining)) before Monk re-engages the shield."
            : "This app will lock again any second now."
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
    static let background = UIColor(red: 12 / 255, green: 14 / 255, blue: 24 / 255, alpha: 0.92)
    static let surface = UIColor(red: 32 / 255, green: 38 / 255, blue: 62 / 255, alpha: 0.96)
    static let primary = UIColor(red: 70 / 255, green: 158 / 255, blue: 255 / 255, alpha: 1.0)
    static let caution = UIColor(red: 255 / 255, green: 115 / 255, blue: 92 / 255, alpha: 1.0)
    static let textPrimary = UIColor(white: 0.96, alpha: 1.0)
    static let textSecondary = UIColor(white: 0.8, alpha: 1.0)
}

private extension ShieldConfiguration.Label {
    static func title(_ text: String) -> ShieldConfiguration.Label {
        .init(text: text, color: SoftBlockShieldPalette.textPrimary)
    }

    static func body(_ text: String) -> ShieldConfiguration.Label {
        .init(text: text, color: SoftBlockShieldPalette.textSecondary)
    }
}

@objc final class SoftBlockShieldUIExtension: ShieldConfigurationDataSource {
    override init() {
        SoftBlockUnlockStore.bootstrap()
        super.init()
    }

    override func configuration(shielding application: ManagedSettings.Application) -> ShieldConfiguration {
        SoftBlockUnlockStore.clearExpired()
        let displayName = application.localizedDisplayName ?? "This app"
        if let token = application.token, let record = SoftBlockUnlockStore.record(for: token) {
            return configuration(for: record, appName: displayName)
        }
        return promptConfiguration(appName: displayName)
    }

    override func configuration(shielding application: ManagedSettings.Application, in category: ManagedSettings.ActivityCategory) -> ShieldConfiguration {
        configuration(shielding: application)
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain) -> ShieldConfiguration {
        return baseConfiguration(
            title: "Web access paused",
            subtitle: "This website is shielded while Monk keeps you focused.",
            primaryLabel: "Back to Monk"
        )
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain, in category: ManagedSettings.ActivityCategory) -> ShieldConfiguration {
        configuration(shielding: webDomain)
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
            primaryLabel: "Stay focused",
            secondaryLabel: "Unlock briefly"
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
            primaryLabel: "Cancel unlock"
        )
    }

    private func unlockedConfiguration(appName: String, remaining: Int) -> ShieldConfiguration {
        return baseConfiguration(
            title: SoftBlockShieldStrings.headline(for: appName),
            subtitle: SoftBlockShieldStrings.unlockedSubtitle(remaining: remaining),
            primaryLabel: "Thanks, Monk"
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
            primaryButtonLabel: .init(text: primaryLabel, color: SoftBlockShieldPalette.textPrimary),
            primaryButtonBackgroundColor: SoftBlockShieldPalette.surface,
            secondaryButtonLabel: secondaryLabel.map { .init(text: $0, color: SoftBlockShieldPalette.caution) }
        )
    }
}
