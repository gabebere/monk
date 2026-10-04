import ServiceManagement
import XCTest
@testable import MonkMac

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testFirstLaunchRegistersAndRemembersLoginItem() {
        let defaults = makeDefaults()
        let service = TestLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service, defaults: defaults)

        controller.registerIfNeeded()
        controller.registerIfNeeded()

        XCTAssertEqual(service.registrationCount, 1)
        XCTAssertTrue(defaults.bool(forKey: LaunchAtLoginController.configurationKey))
    }

    func testPreviouslyConfiguredLoginItemIsNotRestoredAfterUserDisablesIt() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: LaunchAtLoginController.configurationKey)
        let service = TestLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service, defaults: defaults)

        controller.registerIfNeeded()

        XCTAssertEqual(service.registrationCount, 0)
    }

    func testExistingLoginItemIsRecordedWithoutRegisteringAgain() {
        let defaults = makeDefaults()
        let service = TestLaunchAtLoginService(status: .enabled)
        let controller = LaunchAtLoginController(service: service, defaults: defaults)

        controller.registerIfNeeded()

        XCTAssertEqual(service.registrationCount, 0)
        XCTAssertTrue(defaults.bool(forKey: LaunchAtLoginController.configurationKey))
    }

    func testTransientNotFoundStatusStillAttemptsRegistration() {
        let defaults = makeDefaults()
        let service = TestLaunchAtLoginService(status: .notFound)
        let controller = LaunchAtLoginController(service: service, defaults: defaults)

        controller.registerIfNeeded()

        XCTAssertEqual(service.registrationCount, 1)
        XCTAssertTrue(defaults.bool(forKey: LaunchAtLoginController.configurationKey))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "LaunchAtLoginControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

@MainActor
private final class TestLaunchAtLoginService: LaunchAtLoginServicing {
    let status: SMAppService.Status
    private(set) var registrationCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registrationCount += 1
    }
}
