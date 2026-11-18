import CloudKit
import XCTest
@testable import MonkMac

final class CatalogIdentityTests: XCTestCase {
    func testDifferentBundlesWithSameNameHaveDifferentIdentities() {
        let first = CrossDeviceApplication(displayName: "Notes", bundleIdentifier: "com.example.notes")
        let second = CrossDeviceApplication(displayName: "Notes", bundleIdentifier: "com.other.notes")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(first.matches(displayName: second.displayName, bundleIdentifier: second.sourceBundleIdentifier))
    }

    func testRenameDoesNotChangeBundleIdentity() {
        XCTAssertEqual(
            CrossDeviceApplication.stableID(displayName: "Old name", bundleIdentifier: " COM.EXAMPLE.APP "),
            CrossDeviceApplication.stableID(displayName: "New name", bundleIdentifier: "com.example.app")
        )
    }

    func testChatGPTAndCodexRemainDifferentProductsEvenWithSameDisplayName() {
        let chatGPT = CrossDeviceApplication(displayName: "ChatGPT", bundleIdentifier: "com.openai.chat")
        let codex = CrossDeviceApplication(displayName: "ChatGPT", bundleIdentifier: "com.openai.codex")
        XCTAssertNotEqual(chatGPT.id, codex.id)
        XCTAssertNil(match(chatGPT, in: [codex]))
    }

    func testKnownBundlesNeverShareNameBasedTokenMappingKeys() {
        let first = CrossDeviceApplication(displayName: "Notes", bundleIdentifier: "com.example.notes")
        let second = CrossDeviceApplication(displayName: "Notes", bundleIdentifier: "com.other.notes")
        XCTAssertTrue(Set(first.localMappingKeys).isDisjoint(with: second.localMappingKeys))
        XCTAssertEqual(first.localMappingKeys, ["bundle:com.example.notes"])
    }

    func testLegacyNameIDDoesNotOverrideKnownBundleMappingProvenance() {
        let legacy = CrossDeviceApplication(
            id: "name:notes",
            displayName: "Notes",
            sourceBundleIdentifier: "com.example.notes"
        )
        XCTAssertEqual(legacy.localMappingKeys, ["bundle:com.example.notes"])
        XCTAssertFalse(legacy.localMappingKeys.contains("name:notes"))
    }

    func testReviewedPlatformEquivalentsShareCanonicalTokenMappingKey() {
        let desktop = CrossDeviceApplication(displayName: "Safari", bundleIdentifier: "com.apple.Safari")
        let mobile = CrossDeviceApplication(displayName: "Safari", bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertEqual(desktop.localMappingKeys.first, mobile.localMappingKeys.first)
        XCTAssertTrue(mobile.localMappingKeys.contains("bundle:com.apple.mobilesafari"))
    }

    func testExactBundleWinsOverNameAndPlatformEquivalent() {
        let request = CrossDeviceApplication(displayName: "Safari", bundleIdentifier: "com.apple.Safari")
        let candidates = [
            CrossDeviceApplication(displayName: "Safari", bundleIdentifier: "com.apple.mobilesafari"),
            CrossDeviceApplication(displayName: "Renamed Safari", bundleIdentifier: "com.apple.Safari")
        ]
        XCTAssertEqual(match(request, in: candidates), candidates[1])
    }

    func testNameFallbackRequiresUniqueCandidate() {
        let request = CrossDeviceApplication(displayName: "Notes", bundleIdentifier: nil)
        let first = CrossDeviceApplication(displayName: "Notes", bundleIdentifier: "com.example.notes")
        let second = CrossDeviceApplication(displayName: "Notes", bundleIdentifier: "com.other.notes")
        XCTAssertNil(match(request, in: [first, second]))
        XCTAssertEqual(match(request, in: [first]), first)
    }

    func testLegacyNameIdentityStillMatchesByActualBundle() {
        let request = CrossDeviceApplication(
            id: "name:old-name",
            displayName: "Old name",
            sourceBundleIdentifier: "com.example.app"
        )
        let renamed = CrossDeviceApplication(displayName: "Renamed", bundleIdentifier: "com.example.app")
        XCTAssertEqual(match(request, in: [renamed]), renamed)
    }

    func testInstallationIdentityIsStableAndSeparateBetweenStores() {
        let firstSuite = "CatalogIdentityTests.\(UUID().uuidString)"
        let secondSuite = "CatalogIdentityTests.\(UUID().uuidString)"
        let first = UserDefaults(suiteName: firstSuite)!
        let second = UserDefaults(suiteName: secondSuite)!
        defer {
            first.removePersistentDomain(forName: firstSuite)
            second.removePersistentDomain(forName: secondSuite)
        }
        let identity = CrossDeviceCatalogDevice.identifier(in: first)
        XCTAssertNotNil(UUID(uuidString: identity))
        XCTAssertEqual(identity, CrossDeviceCatalogDevice.identifier(in: first))
        XCTAssertNotEqual(identity, CrossDeviceCatalogDevice.identifier(in: second))
    }

    func testTwoMacsHaveDifferentRecordNamesAndRoundTrip() throws {
        let application = CrossDeviceApplication(displayName: "Editor", bundleIdentifier: "com.example.editor")
        let first = CrossDeviceApplicationCatalog(
            deviceID: UUID().uuidString,
            platform: .macOS,
            applications: [application]
        )
        let second = CrossDeviceApplicationCatalog(
            deviceID: UUID().uuidString,
            platform: .macOS,
            applications: [application]
        )
        XCTAssertNotEqual(first.recordName, second.recordName)
        let record = CKRecord(
            recordType: CrossDeviceCloudRecord.applicationCatalogType,
            recordID: CKRecord.ID(recordName: first.recordName)
        )
        first.write(to: record)
        let decoded = try XCTUnwrap(CrossDeviceApplicationCatalog(record: record))
        XCTAssertEqual(decoded.deviceID, first.deviceID)
        XCTAssertEqual(decoded.platform, .macOS)
        XCTAssertEqual(decoded.applications, [application])
        XCTAssertFalse(decoded.isLegacy)
    }

    func testCatalogMergeRetainsBothDevicesAndDistinctSameNameApps() {
        let now = Date()
        let firstApp = CrossDeviceApplication(displayName: "Editor", bundleIdentifier: "com.example.editor")
        let secondApp = CrossDeviceApplication(displayName: "Editor", bundleIdentifier: "com.other.editor")
        let catalogs = [
            CrossDeviceApplicationCatalog(deviceID: UUID().uuidString, platform: .macOS, updatedAt: now, applications: [firstApp]),
            CrossDeviceApplicationCatalog(deviceID: UUID().uuidString, platform: .macOS, updatedAt: now, applications: [secondApp])
        ]
        XCTAssertEqual(Set(CrossDeviceApplicationCatalog.mergedApplications(from: catalogs, now: now)), [firstApp, secondApp])
    }

    func testCatalogMergeUsesNewestMetadataForDuplicateBundle() {
        let now = Date()
        let oldName = CrossDeviceApplication(displayName: "Old", bundleIdentifier: "com.example.app")
        let newName = CrossDeviceApplication(displayName: "New", bundleIdentifier: "com.example.app")
        let catalogs = [
            CrossDeviceApplicationCatalog(deviceID: UUID().uuidString, platform: .macOS, updatedAt: now.addingTimeInterval(-60), applications: [oldName]),
            CrossDeviceApplicationCatalog(deviceID: UUID().uuidString, platform: .iPhone, updatedAt: now, applications: [newName])
        ]
        XCTAssertEqual(CrossDeviceApplicationCatalog.mergedApplications(from: catalogs, now: now), [newName])
    }

    func testCatalogMergeExcludesThisInstallationAndStaleDevices() {
        let now = Date()
        let localID = UUID().uuidString.lowercased()
        let local = CrossDeviceApplicationCatalog(deviceID: localID, platform: .macOS, updatedAt: now, applications: [app("Local")])
        let stale = CrossDeviceApplicationCatalog(
            deviceID: UUID().uuidString,
            platform: .macOS,
            updatedAt: now.addingTimeInterval(-CrossDeviceApplicationCatalog.maximumAge - 1),
            applications: [app("Stale")]
        )
        let fresh = CrossDeviceApplicationCatalog(deviceID: UUID().uuidString, platform: .iPad, updatedAt: now, applications: [app("Fresh")])
        XCTAssertEqual(
            CrossDeviceApplicationCatalog.mergedApplications(from: [local, stale, fresh], excludingDeviceID: localID, now: now),
            [app("Fresh")]
        )
    }

    func testLegacyCatalogIsReadableButSupersededByModernPlatformCatalog() throws {
        let now = Date()
        let legacy = try XCTUnwrap(CrossDeviceApplicationCatalog(record: legacyRecord()))
        XCTAssertTrue(legacy.isLegacy)
        XCTAssertEqual(legacy.platform, .iPhone)
        XCTAssertEqual(CrossDeviceApplicationCatalog.mergedApplications(from: [legacy], now: now), legacy.applications)
        let modern = CrossDeviceApplicationCatalog(deviceID: UUID().uuidString, platform: .iPhone, updatedAt: now, applications: [app("Modern")])
        XCTAssertEqual(CrossDeviceApplicationCatalog.mergedApplications(from: [legacy, modern], now: now), [app("Modern")])
    }

    func testMalformedParallelArraysAreRejected() {
        let record = legacyRecord()
        record["applicationNames"] = ["First", "Extra"] as NSArray
        XCTAssertNil(CrossDeviceApplicationCatalog(record: record))
    }

    func testUnknownFutureCatalogSchemaIsRejected() {
        let record = legacyRecord()
        record["schemaVersion"] = NSNumber(value: CrossDeviceApplicationCatalog.schemaVersion + 1)
        XCTAssertNil(CrossDeviceApplicationCatalog(record: record))
    }

    private func match(
        _ request: CrossDeviceApplication,
        in candidates: [CrossDeviceApplication]
    ) -> CrossDeviceApplication? {
        request.uniqueMatch(in: candidates, displayName: { $0.displayName }, bundleIdentifier: { $0.sourceBundleIdentifier })
    }

    private func app(_ name: String) -> CrossDeviceApplication {
        CrossDeviceApplication(displayName: name, bundleIdentifier: "com.example.\(name.lowercased())")
    }

    private func legacyRecord() -> CKRecord {
        let record = CKRecord(
            recordType: CrossDeviceCloudRecord.applicationCatalogType,
            recordID: CKRecord.ID(recordName: CrossDeviceCloudRecord.iPhoneApplicationCatalogName)
        )
        record["platform"] = "iOS" as CKRecordValue
        record["applicationIDs"] = ["name:legacy"] as NSArray
        record["applicationNames"] = ["Legacy"] as NSArray
        record["applicationBundleIdentifiers"] = ["com.example.legacy"] as NSArray
        return record
    }
}
