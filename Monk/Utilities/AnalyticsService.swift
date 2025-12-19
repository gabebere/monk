import Foundation
import OSLog
#if canImport(PostHog)
import PostHog
#endif
import UIKit

enum Analytics {
    static let shared = AnalyticsService()

    static func configure() {
        shared.configure()
    }

    static func setEnabled(_ enabled: Bool) {
        shared.setEnabled(enabled)
    }

    static func identify(_ id: String) {
        shared.identify(id)
    }

    static func reset() {
        shared.reset()
    }

    static func track(_ name: String, _ props: [String: Any] = [:]) {
        shared.track(name, props)
    }
}

final class AnalyticsService {
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "Analytics")
    private let apiKey = "phc_RIJV9E1BDMFveINBk49EbdUWEIVjy9VkoGjoKH69xrX"
    private let host = "https://us.i.posthog.com"
    private let distinctIdKey = "posthog_distinct_id"
    private let keychainService = "com.gbr.Monk.analytics"
    private let telemetryFlagKey = "telemetry_enabled"
    private var enabled: Bool = true
    private var distinctId: String?
    private var dedupe: [String: Date] = [:]

    func configure() {
        enabled = UserDefaults.standard.object(forKey: telemetryFlagKey) as? Bool ?? true
        let id = loadOrCreateDistinctId()
        distinctId = id
#if canImport(PostHog)
        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.identify(id)
#endif
        logger.debug("Analytics configured with id \(id, privacy: .public), enabled=\(self.enabled, privacy: .public)")
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: telemetryFlagKey)
#if canImport(PostHog)
        // PostHog iOS SDK lacks a global enable toggle; rely on client-side guard.
#endif
        logger.debug("Analytics enabled set to \(enabled, privacy: .public)")
    }

    func identify(_ id: String) {
        distinctId = id
        saveDistinctId(id)
#if canImport(PostHog)
        guard enabled else { return }
        PostHogSDK.shared.identify(id)
#endif
    }

    func reset() {
        let newId = UUID().uuidString
        saveDistinctId(newId)
        distinctId = newId
#if canImport(PostHog)
        PostHogSDK.shared.reset()
        if enabled { PostHogSDK.shared.identify(newId) }
#endif
        logger.debug("Analytics reset with new id \(newId, privacy: .public)")
    }

    func track(_ name: String, _ props: [String: Any] = [:]) {
        guard enabled else { return }
        var properties = props
        properties.merge(baseProperties()) { _, new in new }

        let key = dedupeKey(for: name, props: properties)
        if let last = dedupe[key], Date().timeIntervalSince(last) < 3 { return }
        dedupe[key] = Date()

#if canImport(PostHog)
        PostHogSDK.shared.capture(name, properties: properties)
#endif
    }

    private func baseProperties() -> [String: Any] {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let device = UIDevice.current
        return [
            "app_version": version,
            "build": build,
            "os_version": device.systemVersion,
            "device_class": device.model
        ]
    }

    private func dedupeKey(for name: String, props: [String: Any]) -> String {
        let bucket = Int(Date().timeIntervalSince1970 / 5)
        let session = (props["session_id"] as? String) ?? ""
        return "\(name)|\(session)|\(bucket)"
    }

    private func loadOrCreateDistinctId() -> String {
        if let existing = loadDistinctId() { return existing }
        let newId = UUID().uuidString
        saveDistinctId(newId)
        return newId
    }

    private func loadDistinctId() -> String? {
        if let data = KeychainHelper.load(service: keychainService, account: distinctIdKey),
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        return UserDefaults.standard.string(forKey: distinctIdKey)
    }

    private func saveDistinctId(_ id: String) {
        let data = Data(id.utf8)
        _ = KeychainHelper.save(service: keychainService, account: distinctIdKey, data: data)
        UserDefaults.standard.set(id, forKey: distinctIdKey)
    }
}

private enum KeychainHelper {
    @discardableResult
    static func save(service: String, account: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = query.merging([kSecValueData as String: data]) { $1 }
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
