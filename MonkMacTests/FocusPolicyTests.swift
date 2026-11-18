import Carbon.HIToolbox
import CloudKit
import XCTest
@testable import MonkMac

final class FocusPolicyTests: XCTestCase {
    // MARK: - Cross-device app identity

    func testCrossDeviceApplicationMatchesNamesAcrossPlatformBundleIdentifiers() {
        let application = CrossDeviceApplication(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )

        XCTAssertTrue(
            application.matches(
                displayName: "Safari",
                bundleIdentifier: "com.apple.mobilesafari"
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
        XCTAssertEqual(
            CrossDeviceApplication.fallbackDisplayName(for: "net.whatsapp.WhatsApp"),
            "WhatsApp"
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

    // MARK: - Input and policy rules

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

    func testAuthenticationCompanionsAreAvailableWhenAWebsiteIsAllowed() {
        XCTAssertTrue(
            WebsiteAccessCompanions.expandedDomains(["moodle.example.edu"])
                .contains("login.microsoftonline.com")
        )
        XCTAssertTrue(WebsiteAccessCompanions.expandedDomains([]).isEmpty)
    }

    func testWebsiteNavigationAllowsOneDirectRedirectWithoutCreatingAnUnlimitedChain() {
        var navigation = WebsiteNavigationAllowance(
            domains: ["moodle.example.edu"],
            redirectWindow: 3,
            temporaryLifetime: 600
        )
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(navigation.allows("https://unrelated.example", in: "Safari", at: now))
        XCTAssertTrue(navigation.allows("https://moodle.example.edu/login", in: "Safari", at: now))
        XCTAssertTrue(
            navigation.allows(
                "https://identity.university.example/sign-in",
                in: "Safari",
                at: now.addingTimeInterval(1)
            )
        )
        XCTAssertTrue(
            navigation.allows(
                "https://identity.university.example/continue",
                in: "Safari",
                at: now.addingTimeInterval(20)
            )
        )
        XCTAssertFalse(
            navigation.allows(
                "https://another-unrelated.example",
                in: "Safari",
                at: now.addingTimeInterval(21)
            )
        )
    }

    // MARK: - Session persistence and sync

    func testMicrosoftSignInCompanionCanContinueAnAuthenticationRedirect() {
        var navigation = WebsiteNavigationAllowance(domains: ["moodle.example.edu"])
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(
            navigation.allows(
                "https://login.microsoftonline.com/common/oauth2/authorize",
                in: "Chrome",
                at: now
            )
        )
        XCTAssertTrue(
            navigation.allows(
                "https://moodle.example.edu/auth/oidc/",
                in: "Chrome",
                at: now.addingTimeInterval(1)
            )
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
    func testExpiredPersistedSessionRemainsLockedUntilUserDecides() throws {
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

        XCTAssertEqual(store.activePolicy, expiredPolicy)
        XCTAssertTrue(store.isAwaitingSessionDecision)
        XCTAssertTrue(store.preventsTermination)
        XCTAssertNotNil(defaults.data(forKey: FocusSessionStore.persistedPolicyKey))
        XCTAssertEqual(applicationGuardian.enforcedPolicy, expiredPolicy)
        XCTAssertEqual(websiteGuardian.enforcedPolicy, expiredPolicy)
    }

    @MainActor
    func testCompletedSessionCanBeExtendedOrEnded() throws {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var now = Date(timeIntervalSince1970: 20_000)
        let expiredPolicy = FocusPolicy(
            intention: "Deep work",
            startedAt: Date(timeIntervalSince1970: 10_000),
            duration: 60,
            allowedApplications: [],
            allowedDomains: []
        )
        defaults.set(
            try JSONEncoder().encode(expiredPolicy),
            forKey: FocusSessionStore.persistedPolicyKey
        )
        let syncService = FocusPolicySyncSpy()
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(),
            websiteGuardian: WebsiteGuardianSpy(),
            syncService: syncService,
            defaults: defaults,
            nowProvider: { now }
        )
        store.restorePersistedSessionIfNeeded()

        store.extendExpiredFocus(by: 15 * 60)

        XCTAssertFalse(store.isAwaitingSessionDecision)
        XCTAssertEqual(store.activePolicy?.endsAt, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(syncService.publishedPolicies.last, store.activePolicy)

        let endedCommitment = SyncedFocusCommitment(
            sessionID: expiredPolicy.id,
            intention: expiredPolicy.intention,
            startedAt: expiredPolicy.startedAt,
            endsAt: now,
            allowedDomains: [],
            isEnded: true
        )
        store.startSyncedFocus(endedCommitment)

        XCTAssertNotNil(store.activePolicy)
        let extended = try XCTUnwrap(store.activePolicy)
        now = extended.endsAt
        store.startSyncedFocus(SyncedFocusCommitment(
            sessionID: extended.id, intention: extended.intention, startedAt: extended.startedAt,
            endsAt: extended.endsAt, allowedDomains: extended.allowedDomains, isEnded: true
        ))
        XCTAssertNil(store.activePolicy)
    }

    @MainActor
    func testCloudRoundTripDoesNotReplaceLocalSessionApplications() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 20_000)
        let xcode = ApplicationDescriptor(
            displayName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app")
        )
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(),
            websiteGuardian: WebsiteGuardianSpy(),
            defaults: defaults,
            nowProvider: { now }
        )
        store.start(
            intention: "Build Monk",
            duration: 30 * 60,
            allowedApplications: [xcode],
            allowedDomains: []
        )
        let localPolicy = store.activePolicy!
        let cloudRoundTrip = SyncedFocusCommitment(
            sessionID: localPolicy.id,
            intention: localPolicy.intention,
            startedAt: localPolicy.startedAt,
            endsAt: localPolicy.endsAt.addingTimeInterval(0.25),
            allowedDomains: [],
            allowedApplications: [
                CrossDeviceApplication(
                    displayName: "Xcode",
                    bundleIdentifier: "com.apple.dt.Xcode"
                )
            ]
        )

        store.startSyncedFocus(cloudRoundTrip, resolvedApplications: [])

        XCTAssertEqual(store.activePolicy?.endsAt, cloudRoundTrip.endsAt)
        XCTAssertEqual(store.activePolicy?.allowedApplications, [xcode])
    }

    @MainActor
    func testDefaultBlockingPersistsAndEnforcesAlwaysAllowedApplications() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notes = ApplicationDescriptor(
            displayName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            bundleURL: URL(fileURLWithPath: "/System/Applications/Notes.app")
        )
        let guardian = ApplicationGuardianSpy()
        let store = FocusSessionStore(
            guardian: guardian,
            websiteGuardian: WebsiteGuardianSpy(),
            defaults: defaults
        )

        store.configureDefaultBlocking(enabled: true, alwaysAllowedApplications: [notes])

        XCTAssertTrue(store.defaultBlockingEnabled)
        XCTAssertEqual(store.alwaysAllowedApplications, [notes])
        XCTAssertEqual(guardian.defaultAllowedApplications, [notes])
        XCTAssertTrue(defaults.bool(forKey: FocusSessionStore.defaultBlockingEnabledKey))
        XCTAssertTrue(store.preventsTermination)
    }

    // MARK: - Catalogs and optional integrations

    @MainActor
    func testDefaultBlockingPublishesPortableAlwaysAllowedApplications() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let whatsapp = ApplicationDescriptor(
            mobileApplication: CrossDeviceApplication(
                displayName: "WhatsApp",
                bundleIdentifier: "net.whatsapp.WhatsApp"
            )
        )
        let syncService = FocusPolicySyncSpy()
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(),
            websiteGuardian: WebsiteGuardianSpy(),
            syncService: syncService,
            defaults: defaults
        )

        store.configureDefaultBlocking(
            enabled: true,
            alwaysAllowedApplications: [whatsapp]
        )

        XCTAssertEqual(syncService.defaultAccessUpdates.count, 1)
        XCTAssertTrue(syncService.defaultAccessUpdates[0].enabled)
        XCTAssertEqual(syncService.defaultAccessUpdates[0].applications, [whatsapp])
    }

    @MainActor
    func testMacCatalogFindsMobileOnlyWhatsApp() {
        let catalog = ApplicationCatalog()
        catalog.setMobileApplications([
            CrossDeviceApplication(
                displayName: "WhatsApp",
                bundleIdentifier: "net.whatsapp.WhatsApp"
            )
        ])

        let matches = catalog.matches(for: "whats", excluding: [])

        XCTAssertEqual(matches.map(\.displayName), ["WhatsApp"])
        XCTAssertTrue(matches[0].isRemoteMobileApplication)
    }

    @MainActor
    func testWebsiteHistorySuggestionsMatchPageTitlesAndPreferDefaultBrowser() {
        let service = WebsiteHistorySuggestionService(suggestions: [
            WebsiteHistorySuggestion(
                domain: "learn.example.edu",
                title: "University Moodle",
                browserName: "Chrome",
                score: 20
            ),
            WebsiteHistorySuggestion(
                domain: "moodle.backup.edu",
                title: "Moodle Backup",
                browserName: "Safari",
                score: 1_000_000
            )
        ])

        XCTAssertEqual(
            service.matches(for: "moodle", excluding: []).map(\.domain),
            ["moodle.backup.edu", "learn.example.edu"]
        )
        XCTAssertEqual(
            service.matches(for: "moodle", excluding: ["moodle.backup.edu"]).map(\.domain),
            ["learn.example.edu"]
        )
    }

    @MainActor
    func testTimedFocusAddsSessionAppsWithoutPublishingPermanentAllowlist() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notes = ApplicationDescriptor(
            displayName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            bundleURL: URL(fileURLWithPath: "/System/Applications/Notes.app")
        )
        let xcode = ApplicationDescriptor(
            displayName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app")
        )
        let guardian = ApplicationGuardianSpy()
        let syncService = FocusPolicySyncSpy()
        let store = FocusSessionStore(
            guardian: guardian,
            websiteGuardian: WebsiteGuardianSpy(),
            syncService: syncService,
            defaults: defaults
        )
        store.configureDefaultBlocking(enabled: true, alwaysAllowedApplications: [notes])

        store.start(
            intention: "Build Monk",
            duration: 30 * 60,
            allowedApplications: [xcode],
            allowedDomains: []
        )

        XCTAssertEqual(store.activePolicy?.allowedApplications, [xcode])
        XCTAssertEqual(guardian.focusAlwaysAllowedApplications, [notes])
        XCTAssertEqual(syncService.publishedPolicies.first?.allowedApplications, [xcode])
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

    @MainActor
    func testCompletedFocusIsRecordedOnceByCalendarRecorder() {
        let suiteName = "FocusSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendarRecorder = FocusCalendarRecorderSpy()
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(),
            websiteGuardian: WebsiteGuardianSpy(),
            calendarRecorder: calendarRecorder,
            defaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 10_000) }
        )

        store.start(
            intention: "Build Monk",
            duration: 0,
            allowedApplications: [],
            allowedDomains: []
        )
        store.endExpiredFocus()
        store.endExpiredFocus()

        XCTAssertEqual(calendarRecorder.recordedPolicies.map(\.intention), ["Build Monk"])
    }
}

// MARK: - Test doubles

@MainActor
private final class ApplicationGuardianSpy: ApplicationGuarding {
    var onBlockedApplication: ((String) -> Void)?
    private(set) var enforcedPolicy: FocusPolicy?
    private(set) var defaultAllowedApplications: [ApplicationDescriptor] = []
    private(set) var focusAlwaysAllowedApplications: [ApplicationDescriptor] = []

    func beginEnforcing(
        _ policy: FocusPolicy,
        alwaysAllowing applications: [ApplicationDescriptor]
    ) {
        enforcedPolicy = policy
        focusAlwaysAllowedApplications = applications
        defaultAllowedApplications = []
    }

    func beginDefaultBlocking(allowing applications: [ApplicationDescriptor]) {
        enforcedPolicy = nil
        defaultAllowedApplications = applications
        focusAlwaysAllowedApplications = []
    }

    func stopEnforcing() {
        enforcedPolicy = nil
        defaultAllowedApplications = []
        focusAlwaysAllowedApplications = []
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
    private(set) var endedPolicies: [FocusPolicy] = []
    private(set) var defaultAccessUpdates: [(
        enabled: Bool,
        applications: [ApplicationDescriptor]
    )] = []

    func publish(_ policy: FocusPolicy) {
        publishedPolicies.append(policy)
    }

    func end(_ policy: FocusPolicy) {
        endedPolicies.append(policy)
    }

    func publishDefaultAccess(
        enabled: Bool,
        alwaysAllowedApplications: [ApplicationDescriptor]
    ) {
        defaultAccessUpdates.append((enabled, alwaysAllowedApplications))
    }
}

@MainActor
private final class FocusCalendarRecorderSpy: FocusCalendarRecording {
    private(set) var recordedPolicies: [FocusPolicy] = []

    func recordCompletedFocus(_ policy: FocusPolicy) {
        recordedPolicies.append(policy)
    }
}


extension FocusPolicyTests {
    @MainActor
    func testSyncedMobileOnlyAppsSurviveMacRestoreAndExtension() throws {
        let suite = "FocusPortableIntentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 20_000)
        let mobileOnly = CrossDeviceApplication(displayName: "Mobile Editor", bundleIdentifier: "com.example.mobile-editor")
        let commitment = SyncedFocusCommitment(
            sessionID: UUID(), intention: "Write", startedAt: date.addingTimeInterval(-1_000),
            endsAt: date.addingTimeInterval(-10), allowedDomains: [], allowedApplications: [mobileOnly]
        )
        let first = FocusSessionStore(
            guardian: ApplicationGuardianSpy(), websiteGuardian: WebsiteGuardianSpy(),
            defaults: defaults, nowProvider: { date }
        )
        first.startSyncedFocus(commitment, resolvedApplications: [])
        let sync = FocusPolicySyncSpy()
        let restored = FocusSessionStore(
            guardian: ApplicationGuardianSpy(), websiteGuardian: WebsiteGuardianSpy(),
            syncService: sync, defaults: defaults, nowProvider: { date }
        )
        restored.restorePersistedSessionIfNeeded()
        restored.extendExpiredFocus(by: 600)
        XCTAssertEqual(restored.activePolicy?.portableAllowedApplications, [mobileOnly])
        XCTAssertEqual(sync.publishedPolicies.last?.portableAllowedApplications, [mobileOnly])
        XCTAssertEqual(restored.activePolicy?.allowedApplications, [])
    }

    @MainActor
    func testStaleRemoteEndDoesNotUnlockExtendedMacSession() throws {
        let suite = "FocusStaleEndTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 20_000)
        let id = UUID()
        let sync = FocusPolicySyncSpy()
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(), websiteGuardian: WebsiteGuardianSpy(),
            syncService: sync, defaults: defaults, nowProvider: { date }
        )
        store.startSyncedFocus(SyncedFocusCommitment(
            sessionID: id, intention: "Write", startedAt: date.addingTimeInterval(-1_000),
            endsAt: date.addingTimeInterval(-10), allowedDomains: []
        ))
        store.extendExpiredFocus(by: 600)
        store.startSyncedFocus(SyncedFocusCommitment(
            sessionID: id, intention: "Write", startedAt: date.addingTimeInterval(-1_000),
            endsAt: date.addingTimeInterval(-10), allowedDomains: [], isEnded: true
        ))
        XCTAssertEqual(store.activePolicy?.id, id)
        XCTAssertEqual(store.activePolicy?.endsAt, date.addingTimeInterval(600))
        XCTAssertTrue(store.preventsTermination)
    }
}


extension FocusPolicyTests {
    @MainActor
    func testExpiredOfflineMacCompletesWhenLongerWinningRemoteSessionAlreadyEnded() {
        let suite = "FocusOfflineCompletionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 20_000)
        let store = FocusSessionStore(
            guardian: ApplicationGuardianSpy(), websiteGuardian: WebsiteGuardianSpy(),
            defaults: defaults, nowProvider: { date }
        )
        store.startSyncedFocus(SyncedFocusCommitment(
            sessionID: UUID(), intention: "Offline", startedAt: date.addingTimeInterval(-2_000),
            endsAt: date.addingTimeInterval(-500), allowedDomains: []
        ))
        XCTAssertTrue(store.isAwaitingSessionDecision)
        store.startSyncedFocus(SyncedFocusCommitment(
            sessionID: UUID(), intention: "Winning remote", startedAt: date.addingTimeInterval(-1_500),
            endsAt: date.addingTimeInterval(-100), allowedDomains: [], isEnded: true
        ))
        XCTAssertNil(store.activePolicy)
        XCTAssertFalse(store.preventsTermination)
    }
}
