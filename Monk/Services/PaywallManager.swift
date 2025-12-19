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
                #if DEBUG
                logOfferingsDebug(offerings)
                #endif
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
            Analytics.track("purchase_started", [
                "offering_id": package.offeringIdentifier,
                "package_id": package.identifier
            ])
            let result = try await Purchases.shared.purchase(package: package)
            updateCustomerInfo(result.customerInfo)
            Analytics.track("purchase_completed", [
                "offering_id": package.offeringIdentifier,
                "package_id": package.identifier,
                "entitlement_active": result.customerInfo.entitlements[proEntitlementKey]?.isActive == true
            ])
        } catch {
            errorMessage = error.localizedDescription
            let nsError = error as NSError
            Analytics.track("purchase_failed", [
                "offering_id": package.offeringIdentifier,
                "package_id": package.identifier,
                "error_code": "\(nsError.domain):\(nsError.code)"
            ])
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            updateCustomerInfo(info)
            Analytics.track("restore_completed", [
                "entitlement_active": info.entitlements[proEntitlementKey]?.isActive == true
            ])
        } catch {
            errorMessage = error.localizedDescription
            let nsError = error as NSError
            Analytics.track("restore_failed", ["error_code": "\(nsError.domain):\(nsError.code)"])
        }
    }

    func resetForDebug() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let newId = UUID().uuidString
            _ = try await Purchases.shared.logIn(newId)
            Purchases.shared.invalidateCustomerInfoCache()
            customerInfo = nil
            offerings = nil
            isPro = false
            refresh()
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

    private func logOfferingsDebug(_ offerings: Offerings?) {
        guard let current = offerings?.current else {
            print("RC: offerings.current is nil")
            return
        }
        print("RC: current offering id =", current.identifier)
        if current.paywall != nil {
            print("RC: paywall received for current offering")
        } else {
            print("RC: current.paywall is NIL (will show fallback)")
        }
        let packages = current.availablePackages.map { "\($0.identifier) -> \($0.storeProduct.productIdentifier)" }
        print("RC: packages =", packages)
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
