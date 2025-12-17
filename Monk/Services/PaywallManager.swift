import Foundation
import OSLog
import RevenueCat
import RevenueCatUI
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

// MARK: - RevenueCat service
@MainActor
final class RevenueCatService: ObservableObject {
    @Published private(set) var offerings: Offerings?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isPro: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?
    private let proEntitlementKey = "Monk Subscription"

    init() {
        updatesTask = listenForCustomerUpdates()
        refresh()
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let offerings = try await Purchases.shared.offerings()
                let infoValue = try await Purchases.shared.customerInfo()
                self.offerings = offerings
                updateCustomerInfo(infoValue)
                if let current = offerings.current {
                    print("RC: current offering id =", current.identifier)
                    if current.paywall != nil {
                        print("RC: paywall received for current offering")
                    } else {
                        print("RC: current.paywall is NIL (will show fallback)")
                    }
                    let packages = current.availablePackages.map { "\($0.identifier) -> \($0.storeProduct.productIdentifier)" }
                    print("RC: packages =", packages)
                } else {
                    print("RC: offerings.current is nil")
                }
            } catch {
                errorMessage = error.localizedDescription
                print("RC getOfferings error:", error)
            }
        }
    }

    func purchase(package: Package) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            updateCustomerInfo(result.customerInfo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            updateCustomerInfo(info)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showManageSubscriptions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await Purchases.shared.showManageSubscriptions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setUserIntent(_ intent: String) {
        Purchases.shared.attribution.setAttributes(["intent": intent])
    }

    func logIn(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Purchases.shared.logIn(userId)
            updateCustomerInfo(result.customerInfo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logOut() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.logOut()
            updateCustomerInfo(info)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func apply(customerInfo: CustomerInfo) {
        updateCustomerInfo(customerInfo)
    }

    var activeOffering: Offering? {
        offerings?.current
    }

    private func updateCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        isPro = info.entitlements[proEntitlementKey]?.isActive == true
    }

    private func listenForCustomerUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.updateCustomerInfo(info)
            }
        }
    }
}
