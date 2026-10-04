import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

private enum HardBlockShieldPalette {
    static let primaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.98, alpha: 1)
            : UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1)
    }

    static let secondaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.78, alpha: 1)
            : UIColor(red: 0.28, green: 0.30, blue: 0.38, alpha: 1)
    }

    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.08, blue: 0.11, alpha: 0.94)
            : UIColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 0.94)
    }

    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.03, green: 0.64, blue: 0.60, alpha: 1)
            : UIColor(red: 0.06, green: 0.55, blue: 0.65, alpha: 1)
    }

    static let buttonText = UIColor.white
}

private enum HardBlockShieldCopy {
    static let activeTitle = "You chose what matters right now."
    static let idleTitle = "Nothing is in focus yet."

    static func activeSubtitle(for item: String) -> String {
        "\(item) isn’t in this session. Everything else can wait."
    }

    static func idleSubtitle(for item: String) -> String {
        "\(item) stays blocked until you choose it in Monk."
    }
}

private enum HardBlockShieldState {
    static let appGroupIdentifier = MonkConfiguration.appGroupIdentifier
    static let stateFileName = "crossDeviceFocusState.json"

    static var hasActiveFocus: Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return false
        }
        return FileManager.default.fileExists(
            atPath: containerURL.appendingPathComponent(stateFileName).path
        )
    }
}

@objc final class HardBlockShieldUIExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: ManagedSettings.Application) -> ShieldConfiguration {
        configuration(for: application.localizedDisplayName ?? "This app")
    }

    override func configuration(
        shielding application: ManagedSettings.Application,
        in category: ManagedSettings.ActivityCategory
    ) -> ShieldConfiguration {
        configuration(for: application.localizedDisplayName ?? "This app")
    }

    override func configuration(shielding webDomain: ManagedSettings.WebDomain) -> ShieldConfiguration {
        configuration(for: webDomain.domain ?? "This website")
    }

    override func configuration(
        shielding webDomain: ManagedSettings.WebDomain,
        in category: ManagedSettings.ActivityCategory
    ) -> ShieldConfiguration {
        configuration(for: webDomain.domain ?? "This website")
    }
}

private extension HardBlockShieldUIExtension {
    func configuration(for item: String) -> ShieldConfiguration {
        let hasActiveFocus = HardBlockShieldState.hasActiveFocus
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: HardBlockShieldPalette.background,
            icon: nil,
            title: .init(
                text: hasActiveFocus
                    ? HardBlockShieldCopy.activeTitle
                    : HardBlockShieldCopy.idleTitle,
                color: HardBlockShieldPalette.primaryText
            ),
            subtitle: .init(
                text: hasActiveFocus
                    ? HardBlockShieldCopy.activeSubtitle(for: item)
                    : HardBlockShieldCopy.idleSubtitle(for: item),
                color: HardBlockShieldPalette.secondaryText
            ),
            primaryButtonLabel: .init(
                text: hasActiveFocus ? "Back to Monk" : "Open Monk",
                color: HardBlockShieldPalette.buttonText
            ),
            primaryButtonBackgroundColor: HardBlockShieldPalette.accent
        )
    }
}
