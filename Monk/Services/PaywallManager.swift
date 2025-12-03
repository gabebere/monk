import Foundation
import OSLog
import UIKit
#if canImport(SuperwallKit)
import SuperwallKit
#endif

/// Lightweight wrapper around Superwall so the rest of the app can call a single API
/// without crashing if the SDK is absent in this build environment.
final class PaywallManager {
    static let shared = PaywallManager()
    /// Toggle to disable paywall presentation globally.
    static var isDisabled: Bool = false
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "Paywall")
    private let apiKey = "pk_RFn3-r1at5gu7dfidCjMc"
    private let accessKey = "monk.paywall.unlocked"
    private var didPresentThisSession = false

    private init() {}

    var hasAccess: Bool {
        UserDefaults.standard.bool(forKey: accessKey)
    }

    func markPurchased() {
        UserDefaults.standard.set(true, forKey: accessKey)
        didPresentThisSession = false
    }

    func configure() {
        if PaywallManager.isDisabled { return }
        #if canImport(SuperwallKit)
        Superwall.configure(apiKey: apiKey)
        #else
        logger.info("SuperwallKit not present; paywall will be skipped.")
        #endif
    }

    func presentPaywall(force: Bool = false) {
        if PaywallManager.isDisabled {
            logger.info("Paywall disabled; skipping presentation.")
            return
        }
        if !force {
            if hasAccess { return }
            if didPresentThisSession { return }
            didPresentThisSession = true
        }
        #if canImport(SuperwallKit)
        // Trigger a paywall via placement registration (newer Superwall API).
        Superwall.shared.register(placement: "onboarding_paywall")
        #else
        logger.info("SuperwallKit not available in this build; paywall call ignored.")
        #endif
    }

    private func topMostViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topMostViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }
}
