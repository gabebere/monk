import Carbon.HIToolbox
import CloudKit
import XCTest
@testable import MonkMac

final class FocusPolicyTests: XCTestCase {
    func testCrossDeviceApplicationMatchesNamesAcrossPlatformBundleIdentifiers() {
        let application = CrossDeviceApplication(
            displayName: "ChatGPT",
            bundleIdentifier: "com.openai.codex"
        )

        XCTAssertTrue(
            application.matches(
                displayName: "ChatGPT",
                bundleIdentifier: "com.openai.chat"
            )
        )
        XCTAssertFalse(
            application.matches(
                displayName: "Spotify",
                bundleIdentifier: "com.spotify.client"
            )
        )
    }

    func testBundleIdentifierFallbackProducesAReadableApplicationName() {
        XCTAssertEqual(
            CrossDeviceApplication.fallbackDisplayName(for: "com.spotify.client"),
            "Spotify"
        )
        XCTAssertEqual(
            CrossDeviceApplication.fallbackDisplayName(for: "com.savageinteractive.Procreate"),
            "Procreate"
        )
    }

    func testResolvedDisplayNameReplacesPrivateInitialWithBundleAlias() {
        XCTAssertEqual(
            CrossDeviceApplication.resolvedDisplayName(
                localizedDisplayName: "C",
                bundleIdentifier: "com.openai.chat"
            ),
            "ChatGPT"
        )
        XCTAssertEqual(
            CrossDeviceApplication.resolvedDisplayName(
                localizedDisplayName: "S",
                bundleIdentifier: "com.spotify.client"
            ),
            "Spotify"
        )
    }

    func testResolvedDisplayNameKeepsACompleteLocalizedName() {
        XCTAssertEqual(
            CrossDeviceApplication.resolvedDisplayName(
                localizedDisplayName: "Stremio",
                bundleIdentifier: "com.stremio.stremio"
            ),
            "Stremio"
        )
    }

    func testSyncedCommitmentDecodesPortableAllowedApplications() throws {
        let sessionID = UUID()
        let record = CKRecord(recordType: CrossDeviceFocusSyncService.recordType)
        record["sessionID"] = sessionID.uuidString as CKRecordValue
        record["intention"] = "Study robotics" as CKRecordValue
        record["startedAt"] = Date(timeIntervalSince1970: 10_000) as CKRecordValue
        record["endsAt"] = Date(timeIntervalSince1970: 11_000) as CKRecordValue
        record["allowedDomains"] = [] as NSArray
        record["allowedApplicationIDs"] = ["name:chatgpt"] as NSArray
        record["allowedApplicationNames"] = ["ChatGPT"] as NSArray
        record["allowedApplicationBundleIdentifiers"] = ["com.openai.codex"] as NSArray

        let commitment = try XCTUnwrap(SyncedFocusCommitment(record: record))

        XCTAssertEqual(
            commitment.allowedApplications,
            [
                CrossDeviceApplication(
                    id: "name:chatgpt",
                    displayName: "ChatGPT",
                    sourceBundleIdentifier: "com.openai.codex"
                )
            ]
        )
    }

    func testPolicyUsesBundleIdentifiersAsStableAllowedApplicationIDs() {
        let application = ApplicationDescriptor(
            displayName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app")
        )

        let policy = FocusPolicy(
            intention: "Build Monk",
            duration: 30 * 60,
            allowedApplications: [application],
            allowedDomains: ["developer.apple.com"]
        )

        XCTAssertEqual(policy.allowedApplicationIDs, ["com.apple.dt.Xcode"])
        XCTAssertEqual(policy.allowedDomains, ["developer.apple.com"])
    }

    func testPolicyEndDateUsesRequestedDuration() {
        let start = Date(timeIntervalSince1970: 10_000)
        let policy = FocusPolicy(
            intention: "Study robotics",
            startedAt: start,
            duration: FocusDuration.threeHours.seconds,
            allowedApplications: [],
            allowedDomains: []
        )

        XCTAssertEqual(policy.endsAt.timeIntervalSince(start), 10_800)
    }

    func testApplicationWithoutBundleIdentifierFallsBackToItsPath() {
        let url = URL(fileURLWithPath: "/Applications/Local Tool.app")
        let application = ApplicationDescriptor(
            displayName: "Local Tool",
            bundleIdentifier: nil,
            bundleURL: url
        )

        XCTAssertEqual(application.id, url.standardizedFileURL.path)
    }

    func testPrimaryGlobalShortcutIsOptionSpace() {
        XCTAssertEqual(GlobalHotKeyShortcut.optionSpace.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(GlobalHotKeyShortcut.optionSpace.modifiers, UInt32(optionKey))
    }

    func testDurationComponentsCombineHoursAndMinutes() {
        XCTAssertEqual(FocusDurationComponents.totalMinutes(hours: "1", minutes: "15"), 75)
    }

    func testDurationComponentsLimitMinutesToFiftyNine() {
        XCTAssertEqual(FocusDurationComponents.sanitizedMinutes("75"), "59")
        XCTAssertEqual(FocusDurationComponents.sanitizedHours("123"), "12")
        XCTAssertEqual(FocusDurationComponents.sanitizedMinutes(""), "")
    }

    func testMobileDurationInputCombinesAndClampsFields() {
        XCTAssertEqual(MobileFocusInput.totalMinutes(hours: "1", minutes: "15"), 75)
        XCTAssertEqual(MobileFocusInput.sanitizedHours("12 hours"), "12")
        XCTAssertEqual(MobileFocusInput.sanitizedMinutes("75"), "59")
        XCTAssertEqual(MobileFocusInput.sanitizedMinutes(""), "")
    }

    func testMobileWebsiteNormalizationKeepsOnlyAValidHost() {
        XCTAssertEqual(
            MobileFocusInput.normalizedDomain(" HTTPS://WWW.Netflix.com/watch/123 "),
            "netflix.com"
        )
        XCTAssertNil(MobileFocusInput.normalizedDomain("not a website"))
        XCTAssertNil(MobileFocusInput.normalizedDomain("localhost"))
    }

    func testSupportedBrowserFamiliesCoverSafariAndPopularChromiumBrowsers() {
        XCTAssertEqual(SupportedBrowser.scriptingFamily(for: "com.apple.Safari"), .safari)
        XCTAssertEqual(SupportedBrowser.scriptingFamily(for: "com.google.Chrome"), .chromium)
        XCTAssertEqual(SupportedBrowser.scriptingFamily(for: "company.thebrowser.Browser"), .chromium)
        XCTAssertEqual(SupportedBrowser.scriptingFamily(for: "com.brave.Browser"), .chromium)
        XCTAssertNil(SupportedBrowser.scriptingFamily(for: "org.mozilla.firefox"))
    }

    func testFocusFieldNavigationOrder() {
        XCTAssertEqual(
            FocusCommandField.navigationOrder,
            [.intention, .hours, .minutes, .applications, .websites]
        )
    }

    func testWebsiteAllowlistAllowsDomainsAndSubdomainsOnly() {
        let allowlist = WebsiteAllowlist(domains: ["netflix.com", "www.openai.com"])

        XCTAssertTrue(allowlist.allows("https://netflix.com/watch/123"))
        XCTAssertTrue(allowlist.allows("https://www.netflix.com/browse"))
        XCTAssertTrue(allowlist.allows("https://chat.openai.com"))
        XCTAssertFalse(allowlist.allows("https://google.com/search?q=movie"))
        XCTAssertFalse(allowlist.allows("https://notnetflix.com"))
    }

    func testWebsiteAllowlistTreatsInternalBrowserPagesAsSafe() {
        let allowlist = WebsiteAllowlist(domains: [])

        XCTAssertTrue(allowlist.allows("about:blank"))
        XCTAssertTrue(allowlist.allows("chrome://newtab"))
        XCTAssertFalse(allowlist.allows("view-source:https://example.com"))
    }

    func testWebsiteDomainNormalizationRemovesURLDetails() {
        XCTAssertEqual(
            WebsiteAllowlist.normalizedDomain(" HTTPS://WWW.Netflix.com/watch/123 "),
            "netflix.com"
        )
    }

    @MainActor
    func testFocusSessionPersistsAndRestoresCommitment() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let startDate = Date(timeIntervalSince1970: 10_000)
        let firstApplicationGuardian = ApplicationGuardianSpy()
        let firstWebsiteGuardian = WebsiteGuardianSpy()
        let firstStore = FocusSessionStore(
            guardian: firstApplicationGuardian,
            websiteGuardian: firstWebsiteGuardian,
            defaults: defaults,
            nowProvider: { startDate }
        )

        firstStore.start(
            intention: "Build Monk",
            duration: 30 * 60,
            allowedApplications: [],
            allowedDomains: ["developer.apple.com"]
        )

        let restoredApplicationGuardian = ApplicationGuardianSpy()
        let restoredWebsiteGuardian = WebsiteGuardianSpy()
        let restoredStore = FocusSessionStore(
            guardian: restoredApplicationGuardian,
            websiteGuardian: restoredWebsiteGuardian,
            defaults: defaults,
            nowProvider: { startDate.addingTimeInterval(60) }
        )
        restoredStore.restorePersistedSessionIfNeeded()

        XCTAssertEqual(restoredStore.activePolicy?.intention, "Build Monk")
        XCTAssertTrue(restoredStore.preventsTermination)
        XCTAssertEqual(restoredApplicationGuardian.enforcedPolicy, restoredStore.activePolicy)
        XCTAssertEqual(restoredWebsiteGuardian.enforcedPolicy, restoredStore.activePolicy)
    }

    @MainActor
    func testStartingFocusPublishesCrossDeviceCommitment() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let syncService = FocusPolicySyncSpy()
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(),
            websiteGuardian: WebsiteGuardianSpy(),
            syncService: syncService,
            defaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 10_000) }
        )

        store.start(
            intention: "Study robotics",
            duration: 45 * 60,
            allowedApplications: [],
            allowedDomains: ["chatgpt.com"]
        )

        XCTAssertEqual(syncService.publishedPolicies, [store.activePolicy].compactMap { $0 })
    }

    @MainActor
    func testStartingFocusAutomaticallyIncludesInstalledBrowsersWhenWebsitesAreAllowed() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let safari = ApplicationDescriptor(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(),
            websiteGuardian: WebsiteGuardianSpy(),
            defaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 10_000) },
            installedBrowserProvider: { [safari] }
        )

        store.start(
            intention: "Watch a movie",
            duration: 30 * 60,
            allowedApplications: [],
            allowedDomains: ["netflix.com"]
        )

        XCTAssertEqual(store.activePolicy?.allowedApplications, [safari])
    }

    @MainActor
    func testStartingFocusDoesNotIncludeBrowsersWithoutAllowedWebsites() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let safari = ApplicationDescriptor(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(),
            websiteGuardian: WebsiteGuardianSpy(),
            defaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 10_000) },
            installedBrowserProvider: { [safari] }
        )

        store.start(
            intention: "Write",
            duration: 30 * 60,
            allowedApplications: [],
            allowedDomains: []
        )

        XCTAssertEqual(store.activePolicy?.allowedApplications, [])
    }

    @MainActor
    func testSyncedFocusUsesThisMacsSavedAllowedApplicationsWithoutRepublishing() throws {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let safari = ApplicationDescriptor(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        defaults.set(
            try JSONEncoder().encode([safari]),
            forKey: FocusSessionStore.defaultAllowedApplicationsKey
        )

        let syncService = FocusPolicySyncSpy()
        let applicationGuardian = ApplicationGuardianSpy()
        let store = FocusSessionStore(
            guardian: applicationGuardian,
            websiteGuardian: WebsiteGuardianSpy(),
            syncService: syncService,
            defaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 10_000) }
        )
        let commitment = SyncedFocusCommitment(
            sessionID: UUID(),
            intention: "Watch a movie",
            startedAt: Date(timeIntervalSince1970: 9_900),
            endsAt: Date(timeIntervalSince1970: 11_000),
            allowedDomains: ["netflix.com"]
        )

        store.startSyncedFocus(commitment)

        XCTAssertEqual(store.activePolicy?.id, commitment.sessionID)
        XCTAssertEqual(store.activePolicy?.allowedApplications, [safari])
        XCTAssertEqual(store.activePolicy?.allowedDomains, ["netflix.com"])
        XCTAssertTrue(syncService.publishedPolicies.isEmpty)
        XCTAssertEqual(applicationGuardian.enforcedPolicy, store.activePolicy)
    }

    @MainActor
    func testSyncedFocusUsesResolvedPortableApplicationsFromTheOriginatingDevice() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let stremio = ApplicationDescriptor(
            displayName: "Stremio",
            bundleIdentifier: "com.stremio.stremio",
            bundleURL: URL(fileURLWithPath: "/Applications/Stremio.app")
        )
        let commitment = SyncedFocusCommitment(
            sessionID: UUID(),
            intention: "Watch a movie",
            startedAt: Date(timeIntervalSince1970: 9_900),
            endsAt: Date(timeIntervalSince1970: 11_000),
            allowedDomains: [],
            allowedApplications: [
                CrossDeviceApplication(
                    displayName: "Stremio",
                    bundleIdentifier: "com.stremio.stremio"
                )
            ]
        )
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(),
            websiteGuardian: WebsiteGuardianSpy(),
            defaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 10_000) }
        )

        store.startSyncedFocus(commitment, resolvedApplications: [stremio])

        XCTAssertEqual(store.activePolicy?.allowedApplications, [stremio])
    }

    @MainActor
    func testExpiredPersistedSessionIsNotRestored() throws {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expiredPolicy = FocusPolicy(
            intention: "Old focus",
            startedAt: Date(timeIntervalSince1970: 10_000),
            duration: 60,
            allowedApplications: [],
            allowedDomains: []
        )
        defaults.set(
            try JSONEncoder().encode(expiredPolicy),
            forKey: FocusSessionStore.persistedPolicyKey
        )

        let applicationGuardian = ApplicationGuardianSpy()
        let websiteGuardian = WebsiteGuardianSpy()
        let store = FocusSessionStore(
            guardian: applicationGuardian,
            websiteGuardian: websiteGuardian,
            defaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 20_000) }
        )
        store.restorePersistedSessionIfNeeded()

        XCTAssertNil(store.activePolicy)
        XCTAssertFalse(store.preventsTermination)
        XCTAssertNil(defaults.data(forKey: FocusSessionStore.persistedPolicyKey))
        XCTAssertNil(applicationGuardian.enforcedPolicy)
        XCTAssertNil(websiteGuardian.enforcedPolicy)
    }

    @MainActor
    func testCatalogIncludesSafariSymlinkWhenSafariIsInstalled() throws {
        guard FileManager.default.fileExists(atPath: "/Applications/Safari.app") else {
            throw XCTSkip("Safari is not installed on this Mac")
        }

        let catalog = ApplicationCatalog()
        catalog.reload()

        XCTAssertTrue(catalog.applications.contains { $0.bundleIdentifier == "com.apple.Safari" })
    }
}

@MainActor
private final class ApplicationGuardianSpy: ApplicationGuarding {
    var onBlockedApplication: ((String) -> Void)?
    private(set) var enforcedPolicy: FocusPolicy?

    func beginEnforcing(_ policy: FocusPolicy) {
        enforcedPolicy = policy
    }

    func stopEnforcing() {
        enforcedPolicy = nil
    }
}

@MainActor
private final class WebsiteGuardianSpy: WebsiteGuarding {
    var onBlockedWebsite: ((String) -> Void)?
    private(set) var enforcedPolicy: FocusPolicy?

    func beginEnforcing(_ policy: FocusPolicy) {
        enforcedPolicy = policy
    }

    func stopEnforcing() {
        enforcedPolicy = nil
    }
}

@MainActor
private final class FocusPolicySyncSpy: FocusPolicySyncing {
    private(set) var publishedPolicies: [FocusPolicy] = []

    func publish(_ policy: FocusPolicy) {
        publishedPolicies.append(policy)
    }
}
