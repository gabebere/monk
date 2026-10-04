import XCTest
@testable import MonkMac

final class TemporaryUnlockRequestParserTests: XCTestCase {
    func testParsesOneSpokenApplicationAndDuration() throws {
        let request = try TemporaryUnlockRequestParser.parse(
            "WhatsApp for five minutes",
            installedApplicationNames: ["WhatsApp", "Safari"]
        )

        XCTAssertEqual(request.applicationNames, ["WhatsApp"])
        XCTAssertEqual(request.duration, 5 * 60)
    }

    func testParsesMultipleApplicationsInSpokenOrder() throws {
        let request = try TemporaryUnlockRequestParser.parse(
            "WhatsApp and Safari for one hour and fifteen minutes",
            installedApplicationNames: ["Safari", "WhatsApp", "Photos"]
        )

        XCTAssertEqual(request.applicationNames, ["WhatsApp", "Safari"])
        XCTAssertEqual(request.duration, 75 * 60)
    }

    func testParsesCompactDuration() throws {
        let request = try TemporaryUnlockRequestParser.parse(
            "Photos 1h 5m",
            installedApplicationNames: ["Photos"]
        )

        XCTAssertEqual(request.duration, 65 * 60)
    }

    func testPrefersLongerApplicationName() throws {
        let request = try TemporaryUnlockRequestParser.parse(
            "Chrome Beta for ten minutes",
            installedApplicationNames: ["Chrome", "Chrome Beta"]
        )

        XCTAssertEqual(request.applicationNames, ["Chrome Beta"])
    }

    func testShortApplicationNameDoesNotOverlapALongerMatch() throws {
        let request = try TemporaryUnlockRequestParser.parse(
            "Open X and Chrome Beta for ten minutes",
            installedApplicationNames: ["X", "Chrome", "Chrome Beta"]
        )

        XCTAssertEqual(request.applicationNames, ["X", "Chrome Beta"])
    }

    func testAPlainNumberDefaultsToMinutes() throws {
        let request = try TemporaryUnlockRequestParser.parse(
            "WhatsApp and Safari for 15",
            installedApplicationNames: ["WhatsApp", "Safari"]
        )

        XCTAssertEqual(request.duration, 15 * 60)
    }

    func testRequiresDuration() {
        XCTAssertThrowsError(
            try TemporaryUnlockRequestParser.parse(
                "WhatsApp",
                installedApplicationNames: ["WhatsApp"]
            )
        ) { error in
            XCTAssertEqual(error as? TemporaryUnlockRequestParserError, .missingDuration)
        }
    }
}
