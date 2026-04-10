import EventKit
import Foundation
import OSLog
import SwiftData

struct ReminderListInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceName: String
    let allowsContentModifications: Bool

    var isWritable: Bool { allowsContentModifications }

    var isGroceriesCandidate: Bool {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
            .contains("grocer")
    }
}

enum RemindersSyncKeys {
    static let enabled = "reminders.sync.enabled"
    static let destinationListIdentifier = "reminders.sync.listIdentifier"
    static let excludedListIdentifiers = "reminders.sync.excludedListIdentifiers"
    static let hasSeededGroceriesExclusions = "reminders.sync.hasSeededGroceriesExclusions"
}

enum RemindersSyncStorage {
    static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func decodeIdentifierSet(_ rawValue: String) -> Set<String> {
        Set(
            rawValue
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func encodeIdentifierSet(_ identifiers: Set<String>) -> String {
        identifiers.sorted().joined(separator: "\n")
    }

    static func seededGroceriesExclusions(current: Set<String>,
                                          hasSeeded: Bool,
                                          availableLists: [ReminderListInfo]) -> (identifiers: Set<String>, hasSeeded: Bool) {
        guard !hasSeeded else {
            return (current, true)
        }
        let groceriesIDs = Set(
            availableLists
                .filter(\.isGroceriesCandidate)
                .map(\.id)
        )
        return (current.union(groceriesIDs), true)
    }
}

struct MonkReminderMetadata: Equatable {
    let taskID: UUID
    let parentTaskID: UUID?

    init?(url: URL?) {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.localizedLowercase == "monk",
              components.host?.localizedLowercase == "task" else {
            return nil
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let taskID = UUID(uuidString: path) else {
            return nil
        }

        let parentTaskID = components.queryItems?
            .first(where: { $0.name == "parent" })?
            .value
            .flatMap(UUID.init(uuidString:))

        self.taskID = taskID
        self.parentTaskID = parentTaskID
    }

    static func url(taskID: UUID, parentTaskID: UUID?) -> URL? {
        var components = URLComponents()
        components.scheme = "monk"
        components.host = "task"
        components.path = "/\(taskID.uuidString)"
        if let parentTaskID {
            components.queryItems = [
                URLQueryItem(name: "parent", value: parentTaskID.uuidString)
            ]
        }
        return components.url
    }
}

@MainActor
final class RemindersSyncService {
    static let shared = RemindersSyncService()

    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "RemindersSync")
    private var isSyncing = false

    private init() {}

    func requestAccess() async -> Bool {
        await requestAccessIfNeeded()
    }

    func availableLists() async -> [ReminderListInfo] {
        guard await requestAccessIfNeeded() else { return [] }
        return eventStore.calendars(for: .reminder)
            .map { calendar in
                ReminderListInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceName: calendar.source.title,
                    allowsContentModifications: calendar.allowsContentModifications
                )
            }
            .sorted { lhs, rhs in
                if lhs.title == rhs.title {
                    if lhs.sourceName == rhs.sourceName {
                        return lhs.id < rhs.id
                    }
                    return lhs.sourceName < rhs.sourceName
                }
                return lhs.title < rhs.title
            }
    }

    func sync(modelContext: ModelContext,
              destinationListIdentifier: String?,
              excludedListIdentifiers: Set<String>) async {
        guard await requestAccessIfNeeded() else { return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        let destinationCalendar = calendarForDestination(identifier: destinationListIdentifier)
        let reminders = await fetchReminders(in: calendarsForSync(excluding: excludedListIdentifiers))
            .filter(isScheduledReminder)
        let tasks = (try? modelContext.fetch(FetchDescriptor<FocusTask>())) ?? []

        var tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var tasksByExternalIdentifier: [String: FocusTask] = [:]
        var tasksByCalendarItemIdentifier: [String: FocusTask] = [:]

        for task in tasks {
            if let external = task.reminderExternalIdentifier, !external.isEmpty {
                tasksByExternalIdentifier[external] = task
            }
            if let local = task.reminderCalendarItemIdentifier, !local.isEmpty {
                tasksByCalendarItemIdentifier[local] = task
            }
        }

        var matchedTaskIDs = Set<UUID>()
        var pendingParentIDs: [UUID: UUID] = [:]

        for reminder in reminders {
            let matchedTask = resolveTask(
                for: reminder,
                tasksByID: tasksByID,
                tasksByExternalIdentifier: tasksByExternalIdentifier,
                tasksByCalendarItemIdentifier: tasksByCalendarItemIdentifier
            )

            let task: FocusTask
            if let matchedTask {
                task = matchedTask
                matchedTaskIDs.insert(task.id)
                assignReminderIdentifiers(from: reminder, to: task)

                let remoteTimestamp = reminderTimestamp(reminder)
                if remoteTimestamp.timeIntervalSince(task.updatedAt) > 1 {
                    applyReminder(reminder, to: task)
                } else if task.updatedAt.timeIntervalSince(remoteTimestamp) > 1 {
                    upsertReminderInternal(for: task, destinationCalendar: destinationCalendar)
                }
            } else {
                let created = taskFromReminder(reminder)
                modelContext.insert(created)
                task = created
                tasksByID[created.id] = created
                if let external = created.reminderExternalIdentifier, !external.isEmpty {
                    tasksByExternalIdentifier[external] = created
                }
                if let local = created.reminderCalendarItemIdentifier, !local.isEmpty {
                    tasksByCalendarItemIdentifier[local] = created
                }
                matchedTaskIDs.insert(created.id)
            }

            if let parentTaskID = MonkReminderMetadata(url: reminder.url)?.parentTaskID {
                pendingParentIDs[task.id] = parentTaskID
            }
        }

        for (childTaskID, parentTaskID) in pendingParentIDs {
            guard let child = tasksByID[childTaskID],
                  let parent = tasksByID[parentTaskID],
                  child.id != parent.id else {
                continue
            }
            if child.parent?.id != parent.id {
                child.parent = parent
            }
        }

        var deletedTaskIDs = Set<UUID>()
        var tasksPendingDeletion: [FocusTask] = []

        for task in tasks where !matchedTaskIDs.contains(task.id) && hasReminderIdentifiers(task) {
            markTaskTreeForDeletion(
                startingAt: task,
                deletedTaskIDs: &deletedTaskIDs,
                tasksPendingDeletion: &tasksPendingDeletion
            )
        }

        if !tasksPendingDeletion.isEmpty {
            await deleteReminders(for: tasksPendingDeletion)
            tasksPendingDeletion.forEach(modelContext.delete)
        }

        for task in tasksByID.values {
            guard !matchedTaskIDs.contains(task.id) else { continue }
            guard !deletedTaskIDs.contains(task.id) else { continue }
            guard isScheduledTask(task) else { continue }

            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            upsertReminderInternal(for: task, destinationCalendar: destinationCalendar)
        }

        _ = modelContext.saveOrRollback()
    }

    func upsertReminder(for task: FocusTask,
                        modelContext: ModelContext,
                        destinationListIdentifier: String?) async {
        guard await requestAccessIfNeeded() else { return }

        if !isScheduledTask(task) {
            await deleteReminder(for: task)
            task.reminderExternalIdentifier = nil
            task.reminderCalendarItemIdentifier = nil
            _ = modelContext.saveOrRollback()
            return
        }

        let destinationCalendar = calendarForDestination(identifier: destinationListIdentifier)
        upsertReminderInternal(for: task, destinationCalendar: destinationCalendar)
        _ = modelContext.saveOrRollback()
    }

    func deleteReminderTree(for task: FocusTask) async {
        guard await requestAccessIfNeeded() else { return }
        await deleteReminders(for: taskTree(startingAt: task))
    }

    func deleteReminder(for task: FocusTask) async {
        await deleteReminder(
            taskID: task.id,
            calendarItemIdentifier: task.reminderCalendarItemIdentifier,
            externalIdentifier: task.reminderExternalIdentifier
        )
    }

    func deleteReminder(taskID: UUID,
                        calendarItemIdentifier: String?,
                        externalIdentifier: String?) async {
        guard await requestAccessIfNeeded() else { return }
        await deleteReminderInternal(
            taskID: taskID,
            calendarItemIdentifier: calendarItemIdentifier,
            externalIdentifier: externalIdentifier
        )
    }

}

private extension RemindersSyncService {
    func requestAccessIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .fullAccess, .authorized:
                return true
            case .writeOnly:
                return false
            case .denied, .restricted:
                return false
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    eventStore.requestFullAccessToReminders { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .authorized, .fullAccess:
                return true
            case .writeOnly:
                return false
            case .denied, .restricted:
                return false
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .reminder) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }
    }

    func calendarsForSync(excluding excludedListIdentifiers: Set<String>) -> [EKCalendar] {
        eventStore.calendars(for: .reminder)
            .filter { !excludedListIdentifiers.contains($0.calendarIdentifier) }
    }

    func calendarForDestination(identifier: String?) -> EKCalendar? {
        if let normalized = RemindersSyncStorage.normalizedIdentifier(identifier),
           let calendar = eventStore.calendar(withIdentifier: normalized),
           calendar.allowsContentModifications {
            return calendar
        }
        return eventStore.defaultCalendarForNewReminders()
    }

    func fetchReminders(in calendars: [EKCalendar]) async -> [EKReminder] {
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    func reminderForTask(_ task: FocusTask) -> EKReminder? {
        if let identifier = task.reminderCalendarItemIdentifier,
           let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder {
            return reminder
        }
        return nil
    }

    func reminderForDeletion(calendarItemIdentifier: String?,
                             externalIdentifier: String?,
                             taskID: UUID) async -> EKReminder? {
        if let calendarItemIdentifier,
           let reminder = eventStore.calendarItem(withIdentifier: calendarItemIdentifier) as? EKReminder {
            return reminder
        }

        let reminders = await fetchReminders(in: eventStore.calendars(for: .reminder))
        if let externalIdentifier,
           let match = reminders.first(where: { $0.calendarItemExternalIdentifier == externalIdentifier }) {
            return match
        }

        return reminders.first(where: { monkTaskID(from: $0) == taskID })
    }

    func resolveTask(for reminder: EKReminder,
                     tasksByID: [UUID: FocusTask],
                     tasksByExternalIdentifier: [String: FocusTask],
                     tasksByCalendarItemIdentifier: [String: FocusTask]) -> FocusTask? {
        if let embeddedTaskID = monkTaskID(from: reminder),
           let task = tasksByID[embeddedTaskID] {
            return task
        }
        if let external = reminder.calendarItemExternalIdentifier,
           let task = tasksByExternalIdentifier[external] {
            return task
        }
        let local = reminder.calendarItemIdentifier
        if let task = tasksByCalendarItemIdentifier[local] {
            return task
        }
        return nil
    }

    func monkTaskID(from reminder: EKReminder) -> UUID? {
        MonkReminderMetadata(url: reminder.url)?.taskID
    }

    func reminderTimestamp(_ reminder: EKReminder) -> Date {
        if let modified = reminder.lastModifiedDate {
            return modified
        }
        if let completion = reminder.completionDate {
            return completion
        }
        if let scheduled = scheduledDate(for: reminder) {
            return scheduled
        }
        return Date.distantPast
    }

    func scheduledDate(for reminder: EKReminder) -> Date? {
        reminder.dueDateComponents?.date ?? reminder.startDateComponents?.date
    }

    func isScheduledReminder(_ reminder: EKReminder) -> Bool {
        scheduledDate(for: reminder) != nil
    }

    func applyReminder(_ reminder: EKReminder, to task: FocusTask) {
        let trimmedTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.title = trimmedTitle.isEmpty ? "Untitled Task" : trimmedTitle

        let trimmedNotes = reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
        task.dueDate = scheduledDate(for: reminder)
        task.isCompleted = reminder.isCompleted
        task.completedAt = reminder.completionDate
        task.updatedAt = reminderTimestamp(reminder)

        let recurrence = recurrenceFromReminder(reminder)
        task.recurrence = recurrence.recurrence
        task.recurrenceIntervalDays = recurrence.intervalDays
        task.recurrenceWeekdays = recurrence.weekdays

        assignReminderIdentifiers(from: reminder, to: task)
    }

    func taskFromReminder(_ reminder: EKReminder) -> FocusTask {
        let recurrence = recurrenceFromReminder(reminder)
        let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = reminderTimestamp(reminder)
        let metadata = MonkReminderMetadata(url: reminder.url)
        let trimmedNotes = reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines)

        return FocusTask(
            id: metadata?.taskID ?? UUID(),
            title: title.isEmpty ? "Untitled Task" : title,
            notes: (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil,
            dueDate: scheduledDate(for: reminder),
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completionDate,
            recurrence: recurrence.recurrence,
            recurrenceIntervalDays: recurrence.intervalDays,
            recurrenceWeekdays: recurrence.weekdays,
            createdAt: timestamp == .distantPast ? .now : timestamp,
            updatedAt: timestamp,
            reminderExternalIdentifier: reminder.calendarItemExternalIdentifier,
            reminderCalendarItemIdentifier: reminder.calendarItemIdentifier
        )
    }

    func assignReminderIdentifiers(from reminder: EKReminder, to task: FocusTask) {
        task.reminderExternalIdentifier = reminder.calendarItemExternalIdentifier
        task.reminderCalendarItemIdentifier = reminder.calendarItemIdentifier
    }

    func upsertReminderInternal(for task: FocusTask, destinationCalendar: EKCalendar?) {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard isScheduledTask(task) else { return }

        let reminder = reminderForTask(task) ?? EKReminder(eventStore: eventStore)
        if reminder.calendar == nil {
            reminder.calendar = destinationCalendar ?? eventStore.defaultCalendarForNewReminders()
        }

        reminder.title = title
        reminder.notes = task.notes
        if shouldWriteMonkMetadata(to: reminder) {
            reminder.url = MonkReminderMetadata.url(taskID: task.id, parentTaskID: task.parent?.id)
        }

        let scheduledComponents = dateComponents(from: task.dueDate)
        reminder.startDateComponents = scheduledComponents
        reminder.dueDateComponents = scheduledComponents
        reminder.recurrenceRules = recurrenceRules(for: task)
        reminder.isCompleted = task.isCompleted
        reminder.completionDate = task.isCompleted ? (task.completedAt ?? Date()) : nil

        do {
            try eventStore.save(reminder, commit: true)
            assignReminderIdentifiers(from: reminder, to: task)
            applyReminder(reminder, to: task)
        } catch {
            logger.error("Failed upserting reminder for task \(task.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func shouldWriteMonkMetadata(to reminder: EKReminder) -> Bool {
        reminder.url == nil || MonkReminderMetadata(url: reminder.url) != nil
    }

    func dateComponents(from date: Date?) -> DateComponents? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    func recurrenceRules(for task: FocusTask) -> [EKRecurrenceRule]? {
        switch task.recurrence {
        case .none:
            return nil
        case .daily:
            return [EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: nil
            )]
        case .weekly:
            let weekdays = (task.recurrenceWeekdays ?? [])
                .compactMap(weekdayForRecurrence)
                .map(EKRecurrenceDayOfWeek.init)
            return [EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: weekdays.isEmpty ? nil : weekdays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )]
        case .monthly:
            return [EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                end: nil
            )]
        case .custom:
            let interval = max(1, task.recurrenceIntervalDays ?? 1)
            return [EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: interval,
                end: nil
            )]
        }
    }

    func recurrenceFromReminder(_ reminder: EKReminder) -> (recurrence: TaskRecurrence, intervalDays: Int?, weekdays: [Int]?) {
        guard let rule = reminder.recurrenceRules?.first else {
            return (.none, nil, nil)
        }

        switch rule.frequency {
        case .daily:
            if rule.interval > 1 {
                return (.custom, rule.interval, nil)
            }
            return (.daily, nil, nil)
        case .weekly:
            let weekdays = rule.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue }.sorted()
            return (.weekly, nil, weekdays)
        case .monthly:
            return (.monthly, nil, nil)
        default:
            return (.none, nil, nil)
        }
    }

    func weekdayForRecurrence(_ value: Int) -> EKWeekday? {
        EKWeekday(rawValue: value)
    }

    func isScheduledTask(_ task: FocusTask) -> Bool {
        task.dueDate != nil
    }

    func hasReminderIdentifiers(_ task: FocusTask) -> Bool {
        RemindersSyncStorage.normalizedIdentifier(task.reminderExternalIdentifier) != nil
        || RemindersSyncStorage.normalizedIdentifier(task.reminderCalendarItemIdentifier) != nil
    }

    func taskTree(startingAt root: FocusTask) -> [FocusTask] {
        [root] + root.subtasksUnwrapped.flatMap { taskTree(startingAt: $0) }
    }

    func markTaskTreeForDeletion(startingAt root: FocusTask,
                                 deletedTaskIDs: inout Set<UUID>,
                                 tasksPendingDeletion: inout [FocusTask]) {
        for task in taskTree(startingAt: root) where deletedTaskIDs.insert(task.id).inserted {
            tasksPendingDeletion.append(task)
        }
    }

    func deleteReminders(for tasks: [FocusTask]) async {
        for task in tasks {
            await deleteReminderInternal(
                taskID: task.id,
                calendarItemIdentifier: task.reminderCalendarItemIdentifier,
                externalIdentifier: task.reminderExternalIdentifier
            )
        }
    }

    func deleteReminderInternal(taskID: UUID,
                                calendarItemIdentifier: String?,
                                externalIdentifier: String?) async {
        guard let reminder = await reminderForDeletion(
            calendarItemIdentifier: calendarItemIdentifier,
            externalIdentifier: externalIdentifier,
            taskID: taskID
        ) else {
            return
        }
        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            logger.error("Failed deleting reminder for task \(taskID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
