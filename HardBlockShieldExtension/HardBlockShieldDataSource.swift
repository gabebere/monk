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
            ? UIColor(red: 0.08, green: 0.07, blue: 0.15, alpha: 0.96)
            : UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 0.96)
    }

    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.60, blue: 0.78, alpha: 1)
            : UIColor(red: 0.12, green: 0.50, blue: 0.72, alpha: 1)
    }

    static let buttonText = UIColor.white
}

private enum HardBlockShieldCopy {
    static let title = "You chose what matters right now."
    static let primaryButton = "Back to Monk"

    static func subtitle(for item: String) -> String {
        "\(item) isn’t in this session. Everything else can wait."
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
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: HardBlockShieldPalette.background,
            icon: nil,
            title: .init(
                text: HardBlockShieldCopy.title,
                color: HardBlockShieldPalette.primaryText
            ),
            subtitle: .init(
                text: HardBlockShieldCopy.subtitle(for: item),
                color: HardBlockShieldPalette.secondaryText
            ),
            primaryButtonLabel: .init(
                text: HardBlockShieldCopy.primaryButton,
                color: HardBlockShieldPalette.buttonText
            ),
            primaryButtonBackgroundColor: HardBlockShieldPalette.accent
        )
    }
}
