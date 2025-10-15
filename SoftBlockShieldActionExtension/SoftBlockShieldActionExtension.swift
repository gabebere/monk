import DeviceActivity
import Foundation
import FamilyControls
import ManagedSettings
import OSLog

final class SoftBlockShieldActionExtension: ShieldActionDelegate {
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "SoftBlockAction")
    private let waitDuration: TimeInterval = 20
    private let unlockDuration: TimeInterval = 120

    override init() {
        SoftBlockUnlockStore.bootstrap()
        super.init()
    }

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            handleUnlockRequest(for: application, completionHandler: completionHandler)
        default:
            completionHandler(.none)
        }
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        logger.info("Ignoring unlock for category token — quick unlock not supported.")
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        logger.info("Ignoring unlock for web domain token — quick unlock not supported.")
        completionHandler(.close)
    }

    private func handleUnlockRequest(for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if let existing = SoftBlockUnlockStore.record(for: application) {
            logger.info("Unlock already pending for application token \(existing.id.uuidString)")
            completionHandler(.defer)
            return
        }

        var selection = FamilyActivitySelection()
        selection.applicationTokens.insert(application)

        guard let selectionData = try? JSONEncoder().encode(selection) else {
            logger.error("Failed to encode FamilyActivitySelection for unlock request")
            completionHandler(.none)
            return
        }

        let id = UUID()
        let unlockStart = Date().addingTimeInterval(waitDuration)
        let unlockEnd = unlockStart.addingTimeInterval(unlockDuration)
        let record = SoftBlockUnlockRecord(
            id: id,
            selectionData: selectionData,
            unlockStart: unlockStart,
            unlockEnd: unlockEnd,
            waitDuration: waitDuration,
            unlockDuration: unlockDuration,
            createdAt: Date()
        )

        if scheduleDeviceActivity(for: record) {
            SoftBlockUnlockStore.upsert(record)
            completionHandler(.defer)
        } else {
            completionHandler(.none)
        }
    }

    private func scheduleDeviceActivity(for record: SoftBlockUnlockRecord) -> Bool {
        let center = DeviceActivityCenter()
        let name = DeviceActivity.DeviceActivityName(record.id.uuidString)
        center.stopMonitoring([name])

        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        var startComponents = calendar.dateComponents(components, from: record.unlockStart)
        var endComponents = calendar.dateComponents(components, from: record.unlockEnd)
        startComponents.calendar = calendar
        startComponents.timeZone = TimeZone.current
        endComponents.calendar = calendar
        endComponents.timeZone = TimeZone.current

        if let startDate = startComponents.date, let endDate = endComponents.date, endDate <= startDate,
           let adjustedEnd = calendar.date(byAdding: .day, value: 1, to: endDate) {
            endComponents = calendar.dateComponents(components, from: adjustedEnd)
            endComponents.calendar = calendar
            endComponents.timeZone = TimeZone.current
        }

        let schedule = DeviceActivitySchedule(intervalStart: startComponents, intervalEnd: endComponents, repeats: false)

        do {
            try center.startMonitoring(name, during: schedule)
            logger.info("Scheduled DeviceActivity for unlock record \(record.id.uuidString)")
            return true
        } catch {
            logger.error("Failed to start DeviceActivity monitoring: \(String(describing: error))")
            return false
        }
    }
}
