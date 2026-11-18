import Foundation

enum CrossDeviceCloudRecord {
    static let focusType = "MonkFocusCommitment"
    static let currentFocusName = "current-focus-commitment"
    static let applicationCatalogType = "MonkApplicationCatalog"
    static let macApplicationCatalogName = "application-catalog-macOS"
    static let iPhoneApplicationCatalogName = "application-catalog-iPhone"
    static let iPadApplicationCatalogName = "application-catalog-iPad"
    static let defaultAccessType = "MonkDefaultAccess"
    static let currentDefaultAccessName = "current-default-access"
}

struct CrossDeviceApplication: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let sourceBundleIdentifier: String?

    init(displayName: String, bundleIdentifier: String?) {
        self.displayName = displayName
        self.sourceBundleIdentifier = bundleIdentifier
        self.id = Self.stableID(displayName: displayName, bundleIdentifier: bundleIdentifier)
    }

    init(id: String, displayName: String, sourceBundleIdentifier: String?) {
        self.id = id
        self.displayName = displayName
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    /// Persisted token mappings must carry the same identity provenance as
    /// matching. A legacy name key cannot prove which known bundle it represents.
    var localMappingKeys: [String] {
        if let bundleIdentifier = Self.normalizedBundleIdentifier(sourceBundleIdentifier) {
            let canonical = Self.stableID(displayName: displayName, bundleIdentifier: bundleIdentifier)
            let exact = "bundle:\(bundleIdentifier)"
            return canonical == exact ? [canonical] : [canonical, exact]
        }
        let name = Self.stableID(displayName: displayName, bundleIdentifier: nil)
        return id == name ? [id] : [id, name]
    }

    func matches(displayName: String?, bundleIdentifier: String?) -> Bool {
        if let source = Self.normalizedBundleIdentifier(sourceBundleIdentifier),
           let candidate = Self.normalizedBundleIdentifier(bundleIdentifier) {
            return Self.equivalentBundleIdentifier(source)
                == Self.equivalentBundleIdentifier(candidate)
        }

        guard let displayName else { return false }
        let requestedName = Self.normalized(self.displayName)
        return !requestedName.isEmpty && requestedName == Self.normalized(displayName)
    }

    /// Prefer exact identifiers, then known platform equivalents. A name alone
    /// must resolve to exactly one candidate; it never overrides conflicting IDs.
    func uniqueMatch<Candidate>(
        in candidates: [Candidate],
        displayName: (Candidate) -> String?,
        bundleIdentifier: (Candidate) -> String?
    ) -> Candidate? {
        if let requestedBundle = Self.normalizedBundleIdentifier(sourceBundleIdentifier) {
            let exact = candidates.filter {
                Self.normalizedBundleIdentifier(bundleIdentifier($0)) == requestedBundle
            }
            if !exact.isEmpty { return exact.count == 1 ? exact[0] : nil }

            let equivalents = candidates.filter {
                guard let candidateBundle = Self.normalizedBundleIdentifier(bundleIdentifier($0)) else {
                    return false
                }
                return Self.equivalentBundleIdentifier(requestedBundle)
                    == Self.equivalentBundleIdentifier(candidateBundle)
            }
            if !equivalents.isEmpty { return equivalents.count == 1 ? equivalents[0] : nil }
        }

        let matches = candidates.filter {
            self.matches(displayName: displayName($0), bundleIdentifier: bundleIdentifier($0))
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func stableID(displayName: String, bundleIdentifier: String?) -> String {
        if let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) {
            return "bundle:\(equivalentBundleIdentifier(bundleIdentifier))"
        }

        let normalizedName = normalized(displayName)
        if !normalizedName.isEmpty {
            return "name:\(normalizedName)"
        }

        return "name:unknown"
    }

    static func fallbackDisplayName(for bundleIdentifier: String) -> String {
        let aliases = [
            "com.apple.mobilesafari": "Safari",
            "com.goodnotesapp.x": "Goodnotes",
            "com.google.ios.youtube": "YouTube",
            "com.openai.chat": "ChatGPT",
            "com.spotify.client": "Spotify",
            "net.whatsapp.whatsapp": "WhatsApp"
        ]
        if let alias = aliases[bundleIdentifier.lowercased()] {
            return alias
        }

        let ignoredComponents: Set<String> = [
            "ai", "app", "br", "client", "com", "free", "ios", "ipad",
            "iphone", "mobile", "net", "org", "prod", "release", "x"
        ]
        let component = bundleIdentifier
            .split(separator: ".")
            .map(String.init)
            .reversed()
            .first { !ignoredComponents.contains($0.lowercased()) }
            ?? bundleIdentifier
        let separated = component
            .replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "([A-Za-z])([0-9])",
                with: "$1 $2",
                options: .regularExpression
            )
        return separated.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func resolvedDisplayName(
        localizedDisplayName: String?,
        bundleIdentifier: String?
    ) -> String {
        if let localizedDisplayName {
            let trimmed = localizedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let isBundleIdentifier = bundleIdentifier.map {
                trimmed.caseInsensitiveCompare($0) == .orderedSame
            } ?? false
            if trimmed.count > 1,
               trimmed.caseInsensitiveCompare("Application") != .orderedSame,
               !isBundleIdentifier {
                return trimmed
            }
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return fallbackDisplayName(for: bundleIdentifier)
        }

        return localizedDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Application"
    }

    private static func normalizedBundleIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func equivalentBundleIdentifier(_ identifier: String) -> String {
        // Explicit, reviewed platform equivalents. Unknown bundles never become
        // equivalent merely because their display names happen to be the same.
        switch identifier {
        case "com.apple.safari", "com.apple.mobilesafari":
            return "com.apple.safari"
        case "com.google.chrome", "com.google.chrome.ios":
            return "com.google.chrome"
        case "org.mozilla.firefox", "org.mozilla.ios.firefox":
            return "org.mozilla.firefox"
        default:
            return identifier
        }
    }

    private static func normalized(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
