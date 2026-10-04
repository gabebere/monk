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

    func matches(displayName: String?, bundleIdentifier: String?) -> Bool {
        if let sourceBundleIdentifier,
           let bundleIdentifier,
           sourceBundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
            return true
        }

        guard let displayName else { return false }
        return id == Self.stableID(displayName: displayName, bundleIdentifier: bundleIdentifier)
    }

    static func stableID(displayName: String, bundleIdentifier: String?) -> String {
        let normalizedName = normalized(displayName)
        if !normalizedName.isEmpty {
            return "name:\(normalizedName)"
        }

        return "bundle:\(bundleIdentifier?.lowercased() ?? "unknown")"
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

    private static func normalized(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
