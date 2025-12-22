import Foundation
import OSLog
import UIKit

/// Temporary stub while paywall is removed. All paywall calls are no-ops and access is always granted.
final class PaywallManager {
    static let shared = PaywallManager()
    static var isDisabled: Bool = true
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "Paywall")

    private init() {}

    /// Paywall is effectively removed; always grant access.
    var hasAccess: Bool { true }

    func markPurchased() {
        logger.info("markPurchased called while paywall is disabled.")
    }

    func configure() {
        logger.info("PaywallManager.configure skipped; paywall removed.")
    }

    func presentPaywall(force: Bool = false) {
        logger.info("presentPaywall skipped; paywall flow removed.")
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
