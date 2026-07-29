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
