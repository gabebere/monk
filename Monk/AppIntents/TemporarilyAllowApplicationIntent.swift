import AppIntents
import Foundation

struct MonkApplicationEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "App")
    static let defaultQuery = MonkApplicationQuery()

    let id: String
    let displayName: String
    let bundleIdentifier: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: displayName),
            subtitle: bundleIdentifier.map(LocalizedStringResource.init(stringLiteral:))
        )
    }
}

struct MonkApplicationQuery: EntityStringQuery {
    func entities(for identifiers: [MonkApplicationEntity.ID]) async throws -> [MonkApplicationEntity] {
        let identifiers = Set(identifiers)
        return await allApplications().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [MonkApplicationEntity] {
        let applications = await allApplications()
        let query = Self.normalized(string)
        guard !query.isEmpty else { return applications }

        return applications
            .filter {
                Self.normalized($0.displayName).contains(query)
                    || Self.normalized($0.bundleIdentifier ?? "").contains(query)
            }
            .sorted { lhs, rhs in
                let lhsStartsWithQuery = Self.normalized(lhs.displayName).hasPrefix(query)
                let rhsStartsWithQuery = Self.normalized(rhs.displayName).hasPrefix(query)
                if lhsStartsWithQuery != rhsStartsWithQuery {
                    return lhsStartsWithQuery
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func suggestedEntities() async throws -> [MonkApplicationEntity] {
        await allApplications()
    }

    func allApplications() async -> [MonkApplicationEntity] {
        let applications = await CrossDeviceFocusService.shared.temporaryUnlockApplications()
        return applications.map {
            MonkApplicationEntity(
                id: CrossDeviceFocusService.temporaryUnlockIdentifier(for: $0),
                displayName: $0.displayName,
                bundleIdentifier: $0.bundleIdentifier
            )
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

struct TemporaryUnlockRequestEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Temporary app access")
    static let defaultQuery = TemporaryUnlockRequestQuery()

    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: id))
    }
}

struct TemporaryUnlockRequestQuery: EntityStringQuery {
    func entities(
        for identifiers: [TemporaryUnlockRequestEntity.ID]
    ) async throws -> [TemporaryUnlockRequestEntity] {
        identifiers.map(TemporaryUnlockRequestEntity.init(id:))
    }

    func entities(matching string: String) async throws -> [TemporaryUnlockRequestEntity] {
        let request = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return [] }
        return [TemporaryUnlockRequestEntity(id: request)]
    }

    func suggestedEntities() async throws -> [TemporaryUnlockRequestEntity] {
        []
    }
}

struct TemporarilyAllowApplicationIntent: AppIntent {
    static let title: LocalizedStringResource = "Temporarily Allow Apps"
    static let description = IntentDescription(
        "Temporarily allows one or more installed apps while Monk keeps everything else blocked."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Apps",
        description: "The installed apps to allow.",
        requestValueDialog: "Which apps do you want to allow?"
    )
    var applications: [MonkApplicationEntity]

    @Parameter(
        title: "Duration",
        description: "How long the app should remain available.",
        requestValueDialog: "For how long?"
    )
    var duration: Measurement<UnitDuration>

    static var parameterSummary: some ParameterSummary {
        Summary("Allow \(\.$applications) for \(\.$duration)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let seconds = duration.converted(to: .seconds).value
        let outcomes = try await CrossDeviceFocusService.shared.grantTemporaryAccess(
            to: applications.map(\.id),
            for: seconds
        )
        return .result(dialog: Self.resultDialog(for: outcomes))
    }

    static func resultDialog(
        for outcomes: [TemporaryApplicationGrantOutcome]
    ) -> IntentDialog {
        let alreadyAllowed = outcomes.filter(\.wasAlreadyAllowed).map(\.displayName)
        let temporarilyAllowed = outcomes.filter { !$0.wasAlreadyAllowed }

        var parts: [String] = []
        if !temporarilyAllowed.isEmpty {
            let descriptions = temporarilyAllowed.map { outcome in
                let expiry = outcome.expiresAt ?? .now
                return "\(outcome.displayName) until \(expiry.formatted(date: .omitted, time: .shortened))"
            }
            parts.append("Allowed " + Self.list(descriptions) + ".")
        }
        if !alreadyAllowed.isEmpty {
            parts.append(Self.list(alreadyAllowed) + " already had access.")
        }
        return IntentDialog(LocalizedStringResource(stringLiteral: parts.joined(separator: " ")))
    }

    private static func list(_ values: [String]) -> String {
        guard let last = values.last else { return "" }
        if values.count == 1 { return last }
        if values.count == 2 { return values.joined(separator: " and ") }
        return values.dropLast().joined(separator: ", ") + ", and " + last
    }
}

struct SpokenTemporaryUnlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Monk to Temporarily Allow Apps"
    static let description = IntentDescription(
        "Say one or more installed app names and a duration, such as ‘WhatsApp and Safari for five minutes.’"
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Request",
        description: "The app names and duration.",
        requestValueDialog: "Which apps, and for how long?"
    )
    var request: TemporaryUnlockRequestEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Temporarily allow \(\.$request)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let entities = await MonkApplicationQuery().allApplications()
            let parsedRequest = try TemporaryUnlockRequestParser.parse(
                request.id,
                installedApplicationNames: entities.map(\.displayName)
            )
            let entitiesByName = Dictionary(
                entities.map { ($0.displayName.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let identifiers = parsedRequest.applicationNames.compactMap {
                entitiesByName[$0.lowercased()]?.id
            }
            guard identifiers.count == parsedRequest.applicationNames.count else {
                throw TemporaryUnlockRequestParserError.missingApplication
            }

            let outcomes = try await CrossDeviceFocusService.shared.grantTemporaryAccess(
                to: identifiers,
                for: parsedRequest.duration
            )
            return .result(
                dialog: TemporarilyAllowApplicationIntent.resultDialog(for: outcomes)
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Monk couldn't temporarily allow those apps."
            return .result(
                dialog: IntentDialog(LocalizedStringResource(stringLiteral: message))
            )
        }
    }
}

struct MonkAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SpokenTemporaryUnlockIntent(),
            phrases: [
                "\(.applicationName) \(\.$request)",
                "Ask \(.applicationName) to \(\.$request)",
                "Unlock \(\.$request) with \(.applicationName)"
            ],
            shortTitle: "Temporarily Allow Apps",
            systemImageName: "lock.open.fill"
        )
    }
}
