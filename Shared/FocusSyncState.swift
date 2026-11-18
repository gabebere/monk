import Foundation

/// Portable state only. Screen Time tokens and installed application paths never enter this contract.
struct FocusSyncState: Codable, Equatable {
    let sessionID: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let allowedDomains: [String]
    let allowedApplications: [CrossDeviceApplication]
    let sourcePlatform: String?
    let isEnded: Bool

    init(sessionID: UUID, intention: String, startedAt: Date, endsAt: Date,
         allowedDomains: [String], allowedApplications: [CrossDeviceApplication] = [],
         sourcePlatform: String? = nil, isEnded: Bool = false) {
        self.sessionID = sessionID
        self.intention = intention
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.allowedDomains = allowedDomains
        self.allowedApplications = allowedApplications
        self.sourcePlatform = sourcePlatform
        self.isEnded = isEnded
    }

    /// A delayed end must never erase an extension. Overlapping independent sessions converge
    /// on the longer commitment (UUID breaks ties), so synchronization cannot shorten a timer.
    /// Once sessions no longer overlap, the newer session supersedes the older one.
    static func resolve(_ lhs: Self, _ rhs: Self, now: Date) -> Self {
        if lhs.sessionID == rhs.sessionID {
            if lhs.endsAt != rhs.endsAt { return lhs.endsAt > rhs.endsAt ? lhs : rhs }
            if lhs.isEnded != rhs.isEnded, lhs.endsAt <= now {
                return lhs.isEnded ? lhs : rhs
            }
            if lhs.isEnded != rhs.isEnded { return lhs.isEnded ? rhs : lhs }
            return lhs
        }
        let overlaps = lhs.startedAt < rhs.endsAt && rhs.startedAt < lhs.endsAt
        if overlaps, lhs.endsAt != rhs.endsAt {
            return lhs.endsAt > rhs.endsAt ? lhs : rhs
        }
        if !overlaps, lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt ? lhs : rhs
        }
        return lhs.sessionID.uuidString < rhs.sessionID.uuidString ? lhs : rhs
    }

    func permitsEnding(_ local: Self, now: Date) -> Bool {
        guard isEnded, endsAt <= now, local.endsAt <= now else { return false }
        if sessionID == local.sessionID { return endsAt >= local.endsAt }
        // An offline peer may miss the winning active state and first see its completion.
        // Converge only after both commitments elapsed and this ended state is the winner.
        return Self.resolve(local, self, now: now) == self
    }
}

struct DefaultAccessSyncState: Codable, Equatable {
    let enabled: Bool
    let applications: [CrossDeviceApplication]
    let updatedAt: Date
    /// False means names could not be read on the source device; an empty array is not a clear command.
    let applicationsAreAuthoritative: Bool
    let sourcePlatform: String

    var fingerprint: String {
        let canonical = Self(
            enabled: enabled,
            applications: applications.sorted {
                if $0.id != $1.id { return $0.id < $1.id }
                return $0.displayName < $1.displayName
            }, updatedAt: updatedAt, applicationsAreAuthoritative: applicationsAreAuthoritative,
            sourcePlatform: sourcePlatform
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(canonical).base64EncodedString()) ?? ""
    }

    static func resolve(_ lhs: Self, _ rhs: Self) -> Self {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt ? lhs : rhs }
        return lhs.fingerprint < rhs.fingerprint ? lhs : rhs
    }

    /// Unavailable metadata or partial matching never deletes a user's explicit local choices.
    func resolvedSelection<Token: Hashable>(
        local: Set<Token>, matched: Set<Token>, allRequestedApplicationsResolved: Bool? = nil
    ) -> Set<Token> {
        guard applicationsAreAuthoritative else { return local }
        let complete = allRequestedApplicationsResolved ?? (matched.count == applications.count)
        return complete ? matched : local.union(matched)
    }

    init(enabled: Bool, applications: [CrossDeviceApplication], updatedAt: Date,
         applicationsAreAuthoritative: Bool = true, sourcePlatform: String = "unknown") {
        self.enabled = enabled
        self.applications = applications
        self.updatedAt = updatedAt
        self.applicationsAreAuthoritative = applicationsAreAuthoritative
        self.sourcePlatform = sourcePlatform
    }
}

struct CloudKitSyncMutation: Codable, Identifiable, Equatable {
    let id: UUID
    let focus: FocusSyncState?
    let defaultAccess: DefaultAccessSyncState?

    init(focus: FocusSyncState) {
        id = UUID()
        self.focus = focus
        defaultAccess = nil
    }

    init(defaultAccess: DefaultAccessSyncState) {
        id = UUID()
        focus = nil
        self.defaultAccess = defaultAccess
    }
}

/// The queue is bounded to the newest command for each singleton record, and written atomically.
struct CloudKitSyncJournal: Codable {
    var accountID: String?
    var pending: [CloudKitSyncMutation] = []
    // Retained across sign-out so a still-enforced old focus cannot be uploaded to a new account.
    var sessionAccountIDs: [String: String] = [:]
    var quarantinedSessionIDs: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey { case accountID, pending, sessionAccountIDs, quarantinedSessionIDs }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try values.decodeIfPresent(String.self, forKey: .accountID)
        pending = try values.decodeIfPresent([CloudKitSyncMutation].self, forKey: .pending) ?? []
        sessionAccountIDs = try values.decodeIfPresent([String: String].self, forKey: .sessionAccountIDs) ?? [:]
        quarantinedSessionIDs = try values.decodeIfPresent(Set<String>.self, forKey: .quarantinedSessionIDs) ?? []
    }

    mutating func quarantineUnownedRestore(sessionID: UUID) {
        guard sessionAccountIDs[sessionID.uuidString] == nil,
              !pending.contains(where: { $0.focus?.sessionID == sessionID }) else { return }
        quarantinedSessionIDs.insert(sessionID.uuidString)
    }

    mutating func remember(sessionID: UUID, accountID: String) {
        if sessionAccountIDs[sessionID.uuidString] == nil {
            sessionAccountIDs[sessionID.uuidString] = accountID
            quarantinedSessionIDs.remove(sessionID.uuidString)
        }
    }

    mutating func enqueue(_ mutation: CloudKitSyncMutation, now: Date = .now) {
        if let incoming = mutation.focus {
            let key = incoming.sessionID.uuidString
            guard !quarantinedSessionIDs.contains(key) else { return }
            if let owner = sessionAccountIDs[key], let accountID, owner != accountID { return }
            if let accountID { sessionAccountIDs[key] = accountID }
            if let old = pending.first(where: { $0.focus != nil })?.focus,
               FocusSyncState.resolve(old, incoming, now: now) == old { return }
            pending.removeAll { $0.focus != nil }
        } else if let incoming = mutation.defaultAccess {
            if let old = pending.first(where: { $0.defaultAccess != nil })?.defaultAccess,
               DefaultAccessSyncState.resolve(old, incoming) == old { return }
            pending.removeAll { $0.defaultAccess != nil }
        }
        pending.append(mutation)
    }

    mutating func bind(to accountID: String) {
        if let previous = self.accountID, previous != accountID { pending = [] }
        self.accountID = accountID
        pending.removeAll { mutation in
            guard let focus = mutation.focus,
                  let owner = sessionAccountIDs[focus.sessionID.uuidString] else { return false }
            return owner != accountID
        }
        for mutation in pending {
            if let focus = mutation.focus { sessionAccountIDs[focus.sessionID.uuidString] = accountID }
        }
    }

    mutating func signOut() {
        accountID = nil
        pending = []
    }
}
