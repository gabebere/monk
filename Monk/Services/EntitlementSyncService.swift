import Foundation
import Combine

/// Syncs an entitlement flag via iCloud ubiquitous key-value store so paid access can roam across devices.
final class EntitlementSyncService: ObservableObject {
    @Published private(set) var isEntitled: Bool = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var syncedUserId: String?

    private let store: NSUbiquitousKeyValueStore
    private var observer: AnyCancellable?

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        loadFromStore()
        observer = NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .sink { [weak self] _ in
                self?.loadFromStore()
            }
    }

    func updateFromRevenueCat(isPro: Bool, userId: String?) {
        syncedUserId = userId
        isEntitled = isPro
        lastUpdated = Date()
        writeToStore(isEntitled: isPro, userId: userId, source: "revenuecat")
    }

    func markEntitled(manual: Bool = false, userId: String?) {
        syncedUserId = userId
        isEntitled = true
        lastUpdated = Date()
        writeToStore(isEntitled: true, userId: userId, source: manual ? "manual" : "unknown")
    }

    func clear() {
        isEntitled = false
        lastUpdated = Date()
        syncedUserId = nil
        writeToStore(isEntitled: false, userId: nil, source: "clear")
    }

    private func loadFromStore() {
        let entitled = store.bool(forKey: Keys.entitled)
        let updated = store.object(forKey: Keys.updatedAt) as? Date
        let userId = store.string(forKey: Keys.userId)
        DispatchQueue.main.async {
            self.isEntitled = entitled
            self.lastUpdated = updated
            self.syncedUserId = userId
        }
    }

    private func writeToStore(isEntitled: Bool, userId: String?, source: String) {
        store.set(isEntitled, forKey: Keys.entitled)
        store.set(Date(), forKey: Keys.updatedAt)
        store.set(userId, forKey: Keys.userId)
        store.set(source, forKey: Keys.source)
        store.synchronize()
    }
}

private enum Keys {
    static let entitled = "entitlement.isEntitled"
    static let updatedAt = "entitlement.updatedAt"
    static let userId = "entitlement.userId"
    static let source = "entitlement.source"
}
