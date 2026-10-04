import Foundation

enum WebsiteAccessCompanions {
    static let authenticationDomains: Set<String> = [
        "account.live.com",
        "accounts.google.com",
        "appleid.apple.com",
        "login.live.com",
        "login.microsoft.com",
        "login.microsoftonline.com"
    ]

    static func isAuthenticationURL(_ rawURL: String) -> Bool {
        guard let host = URL(string: rawURL)?.host?.lowercased() else { return false }
        return authenticationDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    static func expandedDomains(_ domains: [String]) -> [String] {
        guard !domains.isEmpty else { return [] }
        return Array(Set(domains).union(authenticationDomains)).sorted()
    }
}
