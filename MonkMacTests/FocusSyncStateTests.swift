import CloudKit
import Foundation
import XCTest
@testable import MonkMac

final class FocusSyncStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 20_000)
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func focus(id: UUID? = nil, start: TimeInterval = 19_000,
                       end: TimeInterval = 21_000, ended: Bool = false) -> FocusSyncState {
        FocusSyncState(sessionID: id ?? firstID, intention: "Write", startedAt: Date(timeIntervalSince1970: start),
                       endsAt: Date(timeIntervalSince1970: end), allowedDomains: ["example.com"], isEnded: ended)
    }

    func testStaleEndCannotEraseSameSessionExtensionInEitherWriteOrder() {
        let ended = focus(end: 19_900, ended: true)
        let extended = focus(end: 21_000)
        XCTAssertEqual(FocusSyncState.resolve(ended, extended, now: now), extended)
        XCTAssertEqual(FocusSyncState.resolve(extended, ended, now: now), extended)
        XCTAssertFalse(ended.permitsEnding(extended, now: now))
    }

    func testEndCannotUnlockBeforeDeadline() {
        let active = focus()
        let earlyEnd = focus(ended: true)
        XCTAssertFalse(earlyEnd.permitsEnding(active, now: now))
        XCTAssertEqual(FocusSyncState.resolve(active, earlyEnd, now: now), active)
    }

    func testMatchingEndAfterExpiryWinsInEitherWriteOrder() {
        let active = focus(end: 19_900)
        let ended = focus(end: 19_900, ended: true)
        XCTAssertTrue(ended.permitsEnding(active, now: now))
        XCTAssertEqual(FocusSyncState.resolve(active, ended, now: now), ended)
        XCTAssertEqual(FocusSyncState.resolve(ended, active, now: now), ended)
    }

    func testOverlappingIndependentSessionsConvergeOnLongerCommitment() {
        let first = focus()
        let second = focus(id: secondID, start: 19_500, end: 22_000)
        XCTAssertEqual(FocusSyncState.resolve(first, second, now: now), second)
        XCTAssertEqual(FocusSyncState.resolve(second, first, now: now), second)
        XCTAssertFalse(focus(id: secondID, end: 19_900, ended: true).permitsEnding(first, now: now))
    }

    func testOfflinePeerCanConvergeAfterLongerWinningSessionAlreadyEnded() {
        let local = focus(start: 18_000, end: 19_000)
        let remoteEnd = focus(id: secondID, start: 18_500, end: 19_900, ended: true)
        XCTAssertTrue(remoteEnd.permitsEnding(local, now: now))
        XCTAssertFalse(remoteEnd.permitsEnding(focus(end: 21_000), now: now))
        let shorterEnd = focus(id: secondID, start: 18_500, end: 18_900, ended: true)
        XCTAssertFalse(shorterEnd.permitsEnding(local, now: now))
    }

    func testEqualDeadlineUsesDeterministicSessionID() {
        let first = focus()
        let second = focus(id: secondID)
        XCTAssertEqual(FocusSyncState.resolve(first, second, now: now), first)
        XCTAssertEqual(FocusSyncState.resolve(second, first, now: now), first)
    }

    func testNonoverlappingNewSessionSupersedesOldCommitment() {
        let old = focus(end: 19_000, ended: true)
        let new = focus(id: secondID, start: 19_100)
        XCTAssertEqual(FocusSyncState.resolve(old, new, now: now), new)
        XCTAssertEqual(FocusSyncState.resolve(new, old, now: now), new)
    }

    func testJournalSurvivesRestartAndCoalescesExtensionAgainstStaleEnd() throws {
        var journal = CloudKitSyncJournal()
        journal.bind(to: "first-account")
        journal.enqueue(CloudKitSyncMutation(focus: focus()), now: now)
        journal.enqueue(CloudKitSyncMutation(focus: focus(end: 22_000)), now: now)
        journal.enqueue(CloudKitSyncMutation(focus: focus(end: 19_900, ended: true)), now: now)
        let restored = try JSONDecoder().decode(CloudKitSyncJournal.self, from: JSONEncoder().encode(journal))
        XCTAssertEqual(restored.accountID, "first-account")
        XCTAssertEqual(restored.pending.count, 1)
        XCTAssertEqual(restored.pending.first?.focus?.endsAt, Date(timeIntervalSince1970: 22_000))
    }

    func testNewAccountDiscardsPreviousAccountsPendingState() {
        var journal = CloudKitSyncJournal()
        journal.bind(to: "first-account")
        journal.enqueue(CloudKitSyncMutation(focus: focus()), now: now)
        journal.bind(to: "second-account")
        XCTAssertTrue(journal.pending.isEmpty)
        XCTAssertEqual(journal.accountID, "second-account")
    }

    func testSessionOwnerCannotMigrateThroughAnAccountChange() throws {
        var journal = CloudKitSyncJournal()
        journal.bind(to: "first-account")
        journal.enqueue(CloudKitSyncMutation(focus: focus()), now: now)
        journal.bind(to: "second-account")
        journal.enqueue(CloudKitSyncMutation(focus: focus()), now: now)
        XCTAssertTrue(journal.pending.isEmpty)
        let restored = try JSONDecoder().decode(CloudKitSyncJournal.self, from: JSONEncoder().encode(journal))
        XCTAssertEqual(restored.sessionAccountIDs[firstID.uuidString], "first-account")
    }

    func testReceivedSessionOwnershipSurvivesSwitchWithoutAnyPendingUpload() {
        var journal = CloudKitSyncJournal()
        journal.bind(to: "first-account")
        journal.remember(sessionID: firstID, accountID: "first-account")
        XCTAssertTrue(journal.pending.isEmpty)
        journal.bind(to: "second-account")
        journal.enqueue(CloudKitSyncMutation(focus: focus()), now: now)
        XCTAssertTrue(journal.pending.isEmpty)
        XCTAssertEqual(journal.sessionAccountIDs[firstID.uuidString], "first-account")
    }

    func testLegacyUnownedRestoreStaysLocalUntilVerifiedRemoteOwnership() {
        var journal = CloudKitSyncJournal()
        journal.quarantineUnownedRestore(sessionID: firstID)
        journal.bind(to: "current-account")
        journal.enqueue(CloudKitSyncMutation(focus: focus()), now: now)
        XCTAssertTrue(journal.pending.isEmpty)
        journal.remember(sessionID: firstID, accountID: "current-account")
        journal.enqueue(CloudKitSyncMutation(focus: focus()), now: now)
        XCTAssertEqual(journal.pending.count, 1)
    }

    func testNewOfflinePendingSessionSurvivesRestoreBeforeFirstAccountBinding() {
        var journal = CloudKitSyncJournal()
        journal.enqueue(CloudKitSyncMutation(focus: focus()), now: now)
        journal.quarantineUnownedRestore(sessionID: firstID)
        journal.bind(to: "first-account")
        XCTAssertEqual(journal.pending.count, 1)
        XCTAssertFalse(journal.quarantinedSessionIDs.contains(firstID.uuidString))
    }

    func testDefaultAccessTiesResolveDeterministicallyAndFingerprintIncludesAuthority() {
        let incomplete = DefaultAccessSyncState(enabled: true, applications: [], updatedAt: now,
                                                applicationsAreAuthoritative: false)
        let complete = DefaultAccessSyncState(enabled: true, applications: [], updatedAt: now)
        XCTAssertNotEqual(incomplete.fingerprint, complete.fingerprint)
        XCTAssertEqual(DefaultAccessSyncState.resolve(incomplete, complete),
                       DefaultAccessSyncState.resolve(complete, incomplete))
        let fractional = DefaultAccessSyncState(enabled: true, applications: [], updatedAt: now.addingTimeInterval(0.01))
        XCTAssertNotEqual(complete.fingerprint, fractional.fingerprint)
    }

    func testUnavailablePortableNamesPreserveLocalSelections() {
        let configuration = DefaultAccessSyncState(enabled: true, applications: [], updatedAt: now,
                                                   applicationsAreAuthoritative: false)
        XCTAssertEqual(configuration.resolvedSelection(local: Set(["local-token"]), matched: Set<String>()), ["local-token"])
    }

    func testPartialMatchingPreservesLocalChoicesUntilAllRequestedAppsResolve() {
        let configuration = DefaultAccessSyncState(enabled: true, applications: [
            CrossDeviceApplication(displayName: "One", bundleIdentifier: "com.example.one"),
            CrossDeviceApplication(displayName: "Two", bundleIdentifier: "com.example.two")
        ], updatedAt: now)
        XCTAssertEqual(configuration.resolvedSelection(local: Set(["local-token"]), matched: Set(["one"])), ["local-token", "one"])
        XCTAssertEqual(configuration.resolvedSelection(local: Set(["local-token"]), matched: Set(["one", "two"])), ["one", "two"])
    }

    func testExplicitAuthoritativeEmptySelectionCanClearLocalChoices() {
        let configuration = DefaultAccessSyncState(enabled: true, applications: [], updatedAt: now)
        XCTAssertTrue(configuration.resolvedSelection(local: Set(["local-token"]), matched: Set<String>()).isEmpty)
    }

    func testMultipleRequestsMappedToOneLocalAppCanCompleteResolution() {
        let configuration = DefaultAccessSyncState(enabled: true, applications: [
            CrossDeviceApplication(displayName: "One", bundleIdentifier: "com.example.one"),
            CrossDeviceApplication(displayName: "Two", bundleIdentifier: "com.example.two")
        ], updatedAt: now)
        XCTAssertEqual(configuration.resolvedSelection(
            local: Set(["old"]), matched: Set(["shared"]), allRequestedApplicationsResolved: true
        ), ["shared"])
    }

    func testCloudRoundTripContainsPortableStateAndDefaultsRemainBackwardCompatible() throws {
        let record = CKRecord(recordType: CrossDeviceCloudRecord.focusType)
        focus().write(to: record)
        XCTAssertEqual(FocusSyncState(record: record), focus())
        XCTAssertNil(record["allowedSelectionData"])
        let defaultsRecord = CKRecord(recordType: CrossDeviceCloudRecord.defaultAccessType)
        defaultsRecord["enabled"] = NSNumber(value: true)
        defaultsRecord["updatedAt"] = now as CKRecordValue
        XCTAssertFalse(try XCTUnwrap(DefaultAccessSyncState(record: defaultsRecord)).applicationsAreAuthoritative)
        defaultsRecord["applicationsAreAuthoritative"] = NSNumber(value: true)
        XCTAssertTrue(try XCTUnwrap(DefaultAccessSyncState(record: defaultsRecord)).applicationsAreAuthoritative)
    }
}
