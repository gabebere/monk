import AppKit
import Foundation
import SQLite3

struct WebsiteHistorySuggestion: Identifiable, Equatable, Sendable {
    let domain: String
    let title: String
    let browserName: String
    let score: Int

    var id: String { domain }
}

@MainActor
final class WebsiteHistorySuggestionService: ObservableObject {
    static let enabledDefaultsKey = "com.gbr.Monk.websiteHistorySuggestionsEnabled"

    @Published private(set) var suggestions: [WebsiteHistorySuggestion] = []
    @Published private(set) var browserHistoryAccessNeeded: [String] = []
    @Published private(set) var isLoading = false

    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    init(suggestions: [WebsiteHistorySuggestion] = []) {
        self.suggestions = suggestions.sorted { $0.score > $1.score }
        hasLoaded = !suggestions.isEmpty
    }

    deinit {
        loadTask?.cancel()
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        let sources = Self.historySources()

        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.loadHistory(from: sources)
            }.value
            guard !Task.isCancelled else { return }
            self?.suggestions = result.suggestions
            self?.browserHistoryAccessNeeded = result.accessNeeded
            self?.isLoading = false
        }
    }

    func reload() {
        loadTask?.cancel()
        hasLoaded = false
        suggestions = []
        browserHistoryAccessNeeded = []
        loadIfNeeded()
    }

    func matches(for query: String, excluding domains: Set<String>) -> [WebsiteHistorySuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return suggestions
            .filter { !domains.contains($0.domain) }
            .filter {
                $0.domain.localizedCaseInsensitiveContains(trimmed) ||
                    $0.title.localizedCaseInsensitiveContains(trimmed)
            }
            .prefix(6)
            .map { $0 }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private nonisolated static func loadHistory(
        from sources: [BrowserHistorySource]
    ) -> WebsiteHistoryLoadResult {
        var suggestionsByDomain: [String: WebsiteHistorySuggestion] = [:]
        var accessNeeded = Set<String>()

        for source in sources {
            let result = read(source)
            if result.wasDenied, source.isDefaultBrowser {
                accessNeeded.insert(source.browserName)
            }
            for suggestion in result.suggestions {
                if let existing = suggestionsByDomain[suggestion.domain],
                   existing.score >= suggestion.score {
                    continue
                }
                suggestionsByDomain[suggestion.domain] = suggestion
            }
        }

        return WebsiteHistoryLoadResult(
            suggestions: suggestionsByDomain.values.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.domain.localizedStandardCompare($1.domain) == .orderedAscending
            },
            accessNeeded: accessNeeded.sorted()
        )
    }

    private nonisolated static func read(
        _ source: BrowserHistorySource
    ) -> BrowserHistoryReadResult {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            source.databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if database != nil { sqlite3_close(database) }
            return BrowserHistoryReadResult(suggestions: [], wasDenied: true)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, source.query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return BrowserHistoryReadResult(suggestions: [], wasDenied: false)
        }
        defer { sqlite3_finalize(statement) }

        var suggestions: [WebsiteHistorySuggestion] = []
        var rowIndex = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(statement, 0) else { continue }
            let rawURL = String(cString: urlText)
            guard let domain = WebsiteAllowlist.normalizedDomain(rawURL) else { continue }
            let title = sqlite3_column_text(statement, 1).map(String.init(cString:)) ?? domain
            let visitCount = max(0, Int(sqlite3_column_int(statement, 2)))
            let sourcePriority = source.isDefaultBrowser ? 1_000_000 : 0
            let score = sourcePriority + max(0, 10_000 - rowIndex) + min(visitCount, 500)
            suggestions.append(
                WebsiteHistorySuggestion(
                    domain: domain,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    browserName: source.browserName,
                    score: score
                )
            )
            rowIndex += 1
        }
        return BrowserHistoryReadResult(suggestions: suggestions, wasDenied: false)
    }

    private static func historySources() -> [BrowserHistorySource] {
        let defaultBrowserIdentifier = NSWorkspace.shared
            .urlForApplication(toOpen: URL(string: "https://example.com")!)
            .flatMap(Bundle.init(url:))?
            .bundleIdentifier
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
        let applicationSupport = library
            .appendingPathComponent("Application Support", isDirectory: true)

        var sources: [BrowserHistorySource] = [
            BrowserHistorySource(
                browserName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                databaseURL: library.appendingPathComponent("Safari/History.db"),
                query: """
                    SELECT history_items.url, COALESCE(history_visits.title, ''), history_items.visit_count
                    FROM history_visits
                    JOIN history_items ON history_items.id = history_visits.history_item
                    ORDER BY history_visits.visit_time DESC
                    LIMIT 2000
                    """,
                isDefaultBrowser: defaultBrowserIdentifier?.hasPrefix("com.apple.Safari") == true
            )
        ]

        sources += chromiumSources(
            browserName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            root: applicationSupport.appendingPathComponent("Google/Chrome"),
            defaultBrowserIdentifier: defaultBrowserIdentifier
        )
        sources += chromiumSources(
            browserName: "Brave",
            bundleIdentifier: "com.brave.Browser",
            root: applicationSupport.appendingPathComponent("BraveSoftware/Brave-Browser"),
            defaultBrowserIdentifier: defaultBrowserIdentifier
        )
        sources += chromiumSources(
            browserName: "Edge",
            bundleIdentifier: "com.microsoft.edgemac",
            root: applicationSupport.appendingPathComponent("Microsoft Edge"),
            defaultBrowserIdentifier: defaultBrowserIdentifier
        )
        sources += chromiumSources(
            browserName: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            root: applicationSupport.appendingPathComponent("Arc/User Data"),
            defaultBrowserIdentifier: defaultBrowserIdentifier
        )
        sources += chromiumSources(
            browserName: "Vivaldi",
            bundleIdentifier: "com.vivaldi.Vivaldi",
            root: applicationSupport.appendingPathComponent("Vivaldi"),
            defaultBrowserIdentifier: defaultBrowserIdentifier
        )
        sources += firefoxSources(
            root: applicationSupport.appendingPathComponent("Firefox/Profiles"),
            isDefaultBrowser: defaultBrowserIdentifier == "org.mozilla.firefox"
        )

        return sources
            .filter { FileManager.default.fileExists(atPath: $0.databaseURL.path) }
            .sorted {
                if $0.isDefaultBrowser != $1.isDefaultBrowser { return $0.isDefaultBrowser }
                return $0.browserName.localizedStandardCompare($1.browserName) == .orderedAscending
            }
    }

    private static func chromiumSources(
        browserName: String,
        bundleIdentifier: String,
        root: URL,
        defaultBrowserIdentifier: String?
    ) -> [BrowserHistorySource] {
        let profileURLs = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return profileURLs
            .filter {
                $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ")
            }
            .map {
                BrowserHistorySource(
                    browserName: browserName,
                    bundleIdentifier: bundleIdentifier,
                    databaseURL: $0.appendingPathComponent("History"),
                    query: """
                        SELECT url, COALESCE(title, ''), visit_count
                        FROM urls
                        WHERE hidden = 0
                        ORDER BY last_visit_time DESC
                        LIMIT 2000
                        """,
                    isDefaultBrowser: defaultBrowserIdentifier == bundleIdentifier
                )
            }
    }

    private static func firefoxSources(
        root: URL,
        isDefaultBrowser: Bool
    ) -> [BrowserHistorySource] {
        let profileURLs = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return profileURLs.map {
            BrowserHistorySource(
                browserName: "Firefox",
                bundleIdentifier: "org.mozilla.firefox",
                databaseURL: $0.appendingPathComponent("places.sqlite"),
                query: """
                    SELECT url, COALESCE(title, ''), visit_count
                    FROM moz_places
                    WHERE hidden = 0
                    ORDER BY last_visit_date DESC
                    LIMIT 2000
                    """,
                isDefaultBrowser: isDefaultBrowser
            )
        }
    }
}

private struct BrowserHistorySource: Sendable {
    let browserName: String
    let bundleIdentifier: String
    let databaseURL: URL
    let query: String
    let isDefaultBrowser: Bool
}

private struct BrowserHistoryReadResult: Sendable {
    let suggestions: [WebsiteHistorySuggestion]
    let wasDenied: Bool
}

private struct WebsiteHistoryLoadResult: Sendable {
    let suggestions: [WebsiteHistorySuggestion]
    let accessNeeded: [String]
}
