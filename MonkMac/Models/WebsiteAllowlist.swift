import Foundation

struct WebsiteAllowlist: Equatable {
    let domains: [String]

    init(domains: [String]) {
        self.domains = Array(Set(domains.compactMap(Self.normalizedDomain))).sorted()
    }

    func allows(_ rawURL: String) -> Bool {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return true }

        if trimmedURL.lowercased().hasPrefix("view-source:") {
            return allows(String(trimmedURL.dropFirst("view-source:".count)))
        }

        if trimmedURL.lowercased().hasPrefix("blob:") {
            return allows(String(trimmedURL.dropFirst("blob:".count)))
        }

        guard let url = URL(string: trimmedURL), let scheme = url.scheme?.lowercased() else {
            return false
        }

        guard scheme == "http" || scheme == "https" else {
            return Self.safeLocalSchemes.contains(scheme)
        }

        guard let host = url.host?.lowercased() else { return false }
        return domains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    static func normalizedDomain(_ rawValue: String) -> String? {
        var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return nil }

        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }

        guard let host = URL(string: candidate)?.host?
            .trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            !host.isEmpty else {
            return nil
        }

        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func displayHost(for rawURL: String) -> String {
        if let host = URL(string: rawURL)?.host, !host.isEmpty {
            return host
        }
        return "website"
    }

    private static let safeLocalSchemes: Set<String> = [
        "about",
        "brave",
        "chrome",
        "data",
        "edge",
        "favorites",
        "file",
        "safari-extension"
    ]
}

struct WebsiteNavigationAllowance {
    private let allowlist: WebsiteAllowlist
    private let redirectWindow: TimeInterval
    private let temporaryLifetime: TimeInterval
    private var redirectOpportunityByBrowser: [String: Date] = [:]
    private var temporaryHostsByBrowser: [String: [String: Date]] = [:]

    init(
        domains: [String],
        redirectWindow: TimeInterval = 3,
        temporaryLifetime: TimeInterval = 10 * 60
    ) {
        allowlist = WebsiteAllowlist(domains: domains)
        self.redirectWindow = redirectWindow
        self.temporaryLifetime = temporaryLifetime
    }

    mutating func allows(_ rawURL: String, in browserIdentifier: String, at now: Date) -> Bool {
        removeExpiredAllowances(at: now)

        if allowlist.allows(rawURL) {
            if Self.httpHost(for: rawURL) != nil {
                redirectOpportunityByBrowser[browserIdentifier] = now.addingTimeInterval(redirectWindow)
            }
            return true
        }

        if !allowlist.domains.isEmpty,
           WebsiteAccessCompanions.isAuthenticationURL(rawURL) {
            redirectOpportunityByBrowser[browserIdentifier] = now.addingTimeInterval(redirectWindow)
            return true
        }

        guard let host = Self.httpHost(for: rawURL) else { return false }
        if let expiry = temporaryHostsByBrowser[browserIdentifier]?[host], expiry >= now {
            return true
        }

        guard let opportunity = redirectOpportunityByBrowser[browserIdentifier], opportunity >= now else {
            return false
        }

        redirectOpportunityByBrowser[browserIdentifier] = nil
        temporaryHostsByBrowser[browserIdentifier, default: [:]][host] = now.addingTimeInterval(temporaryLifetime)
        return true
    }

    private mutating func removeExpiredAllowances(at now: Date) {
        redirectOpportunityByBrowser = redirectOpportunityByBrowser.filter { $0.value >= now }
        temporaryHostsByBrowser = temporaryHostsByBrowser.compactMapValues { hosts in
            let activeHosts = hosts.filter { $0.value >= now }
            return activeHosts.isEmpty ? nil : activeHosts
        }
    }

    private static func httpHost(for rawURL: String) -> String? {
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url.host?.lowercased()
    }
}
