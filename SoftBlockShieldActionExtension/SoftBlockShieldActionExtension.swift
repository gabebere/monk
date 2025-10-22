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
            if HardBlockStateStore.isActive && HardBlockStateStore.contains(application: application) {
                completionHandler(.close)
                return
            }

            if SoftBlockUnlockStore.record(for: application) != nil {
                completionHandler(.defer)
                return
            }

            logger.info("Scheduling soft block unlock for token \(String(describing: application), privacy: .public)")
            scheduleUnlock(for: application, completionHandler: completionHandler)

        case .secondaryButtonPressed:
            cancelPendingUnlock(for: application)
            completionHandler(.close)

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

    private func scheduleUnlock(for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        var selection = FamilyActivitySelection()
        selection.applicationTokens.insert(application)

        guard let selectionData = try? JSONEncoder().encode(selection) else {
            logger.error("Failed to encode FamilyActivitySelection for unlock request")
            completionHandler(.none)
            return
        }

        let now = Date()
        let unlockStart = now.addingTimeInterval(waitDuration)
        let unlockEnd = unlockStart.addingTimeInterval(unlockDuration)
        let record = SoftBlockUnlockRecord(
            id: UUID(),
            selectionData: selectionData,
            unlockStart: unlockStart,
            unlockEnd: unlockEnd,
            waitDuration: waitDuration,
            unlockDuration: unlockDuration,
            createdAt: now
        )

        if scheduleDeviceActivity(for: record) {
            SoftBlockUnlockStore.upsert(record)
            completionHandler(.defer)
        } else {
            logger.error("Failed to schedule DeviceActivity for unlock record \(record.id.uuidString, privacy: .public)")
            completionHandler(.none)
        }
    }

    private func scheduleDeviceActivity(for record: SoftBlockUnlockRecord) -> Bool {
        let center = DeviceActivityCenter()
        let name = DeviceActivity.DeviceActivityName(record.id.uuidString)
        center.stopMonitoring([name])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.autoupdatingCurrent
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        var startComponents = calendar.dateComponents(components, from: record.unlockStart)
        var endComponents = calendar.dateComponents(components, from: record.unlockEnd)
        startComponents.calendar = calendar
        startComponents.timeZone = calendar.timeZone
        endComponents.calendar = calendar
        endComponents.timeZone = calendar.timeZone

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

    private func cancelPendingUnlock(for application: ApplicationToken) {
        guard let record = SoftBlockUnlockStore.record(for: application) else { return }
        SoftBlockUnlockStore.remove(id: record.id)
        let center = DeviceActivityCenter()
        center.stopMonitoring([DeviceActivity.DeviceActivityName(record.id.uuidString)])
    }
}
