import Foundation
import ManagedSettings

struct TemporaryApplicationGrant: Codable, Equatable, Identifiable {
    let id: UUID
    let applicationIdentifier: String
    let displayName: String
    let applicationToken: ManagedSettings.ApplicationToken
    let grantedAt: Date
    var expiresAt: Date
}

enum TemporaryApplicationGrantStore {
    static let grantsKey = "crossDeviceFocus.temporaryApplicationGrants"
    static let baseAllowedTokensKey = "crossDeviceFocus.baseAllowedApplicationTokens"
    static let applicationShieldIsActiveKey = "crossDeviceFocus.applicationShieldIsActive"
    static let activityNamePrefix = "TemporaryApplicationGrant."
    static let maximumConcurrentGrants = 10

    static func activeGrants(
        from defaults: UserDefaults,
        at date: Date = .now
    ) -> [TemporaryApplicationGrant] {
        guard let data = defaults.data(forKey: grantsKey),
              let grants = try? JSONDecoder().decode([TemporaryApplicationGrant].self, from: data) else {
            return []
        }
        return grants
            .filter { $0.expiresAt > date }
            .sorted { $0.expiresAt < $1.expiresAt }
    }

    static func save(_ grants: [TemporaryApplicationGrant], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(grants) else { return }
        defaults.set(data, forKey: grantsKey)
    }

    static func baseAllowedTokens(
        from defaults: UserDefaults
    ) -> Set<ManagedSettings.ApplicationToken> {
        guard let data = defaults.data(forKey: baseAllowedTokensKey),
              let tokens = try? JSONDecoder().decode(
                  Set<ManagedSettings.ApplicationToken>.self,
                  from: data
              ) else {
            return []
        }
        return tokens
    }

    static func saveBaseAllowedTokens(
        _ tokens: Set<ManagedSettings.ApplicationToken>,
        to defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        defaults.set(data, forKey: baseAllowedTokensKey)
        defaults.set(true, forKey: applicationShieldIsActiveKey)
    }

    static func combinedAllowedTokens(
        baseTokens: Set<ManagedSettings.ApplicationToken>,
        grants: [TemporaryApplicationGrant]
    ) -> Set<ManagedSettings.ApplicationToken> {
        baseTokens.union(grants.map(\.applicationToken))
    }

    static func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: grantsKey)
        defaults.removeObject(forKey: baseAllowedTokensKey)
        defaults.set(false, forKey: applicationShieldIsActiveKey)
    }

    static func activityName(for grant: TemporaryApplicationGrant) -> String {
        activityNamePrefix + grant.id.uuidString
    }
}
