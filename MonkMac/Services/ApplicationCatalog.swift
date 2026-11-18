import AppKit
import Foundation

@MainActor
final class ApplicationCatalog: ObservableObject {
    @Published private(set) var applications: [ApplicationDescriptor] = []
    @Published private(set) var mobileApplications: [ApplicationDescriptor] = []

    var supportedBrowsers: [ApplicationDescriptor] {
        applications.filter {
            SupportedBrowser.canEnforceWebsites(in: $0.bundleIdentifier)
        }
    }

    func reload() {
        var discovered: [String: ApplicationDescriptor] = [:]

        for directory in applicationDirectories {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: []
            ) else {
                continue
            }

            for url in urls where
                !url.lastPathComponent.hasPrefix(".") &&
                url.pathExtension.lowercased() == "app" {
                guard let application = descriptor(for: url) else { continue }
                discovered[application.id] = application
            }
        }

        applications = discovered.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    func matches(for query: String, excluding selected: Set<String>) -> [ApplicationDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seen = Set<String>()
        return (applications + mobileApplications)
            .filter { !selected.contains($0.id) }
            .filter {
                $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
                    ($0.bundleIdentifier?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
            .filter {
                seen.insert(
                    CrossDeviceApplication.stableID(
                        displayName: $0.displayName,
                        bundleIdentifier: $0.bundleIdentifier
                    )
                ).inserted
            }
            .prefix(6)
            .map { $0 }
    }

    func setMobileApplications(_ applications: [CrossDeviceApplication]) {
        mobileApplications = applications
            .filter {
                $0.uniqueMatch(
                    in: self.applications,
                    displayName: { $0.displayName },
                    bundleIdentifier: { $0.bundleIdentifier }
                ) == nil
            }
            .map(ApplicationDescriptor.init(mobileApplication:))
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    private var applicationDirectories: [URL] {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)

        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            homeApplications
        ]
    }

    private func descriptor(for url: URL) -> ApplicationDescriptor? {
        guard let bundle = Bundle(url: url) else { return nil }
        let displayName =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            url.deletingPathExtension().lastPathComponent

        return ApplicationDescriptor(
            displayName: displayName,
            bundleIdentifier: bundle.bundleIdentifier,
            bundleURL: url
        )
    }
}
