import Foundation
import SwiftData

@Model
final class FocusTask {
    var id: UUID = Foundation.UUID()
    var title: String = ""
    var notes: String?

    var dueDate: Date?

    var isCompleted: Bool = false
    var completedAt: Date?

    var recurrence: TaskRecurrence = TaskRecurrence.none
    var recurrenceIntervalDays: Int?
    var recurrenceWeekdays: [Int]?

    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var reminderExternalIdentifier: String?
    var reminderCalendarItemIdentifier: String?
    var focusToolsSelectionData: Data?
    var hasConfiguredFocusTools: Bool = false

    @Relationship(deleteRule: .nullify) var project: Project?
    @Relationship(deleteRule: .nullify) var parent: FocusTask?
    @Relationship(deleteRule: .cascade, inverse: \FocusTask.parent) var subtasks: [FocusTask]?
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.task) var sessions: [FocusSession]?

    init(id: UUID = UUID(),
         title: String,
         notes: String? = nil,
         dueDate: Date? = nil,
         isCompleted: Bool = false,
         completedAt: Date? = nil,
         recurrence: TaskRecurrence = TaskRecurrence.none,
         recurrenceIntervalDays: Int? = nil,
         recurrenceWeekdays: [Int]? = nil,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         reminderExternalIdentifier: String? = nil,
         reminderCalendarItemIdentifier: String? = nil,
         focusToolsSelectionData: Data? = nil,
         hasConfiguredFocusTools: Bool = false,
         project: Project? = nil,
         parent: FocusTask? = nil,
         subtasks: [FocusTask]? = nil,
         sessions: [FocusSession]? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.recurrence = recurrence
        self.recurrenceIntervalDays = recurrenceIntervalDays
        self.recurrenceWeekdays = recurrenceWeekdays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reminderExternalIdentifier = reminderExternalIdentifier
        self.reminderCalendarItemIdentifier = reminderCalendarItemIdentifier
        self.focusToolsSelectionData = focusToolsSelectionData
        self.hasConfiguredFocusTools = hasConfiguredFocusTools
        self.project = project
        self.parent = parent
        self.subtasks = subtasks
        self.sessions = sessions
    }
}

extension FocusTask {
    var subtasksUnwrapped: [FocusTask] { subtasks ?? [] }
    var sessionsUnwrapped: [FocusSession] { sessions ?? [] }
    var isScheduled: Bool { dueDate != nil }
    var isReminderBacked: Bool {
        let external = reminderExternalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let local = reminderCalendarItemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !external.isEmpty || !local.isEmpty
    }
    var taskTree: [FocusTask] {
        [self] + subtasksUnwrapped.flatMap { $0.taskTree }
    }

    var displayTitle: String {
        if let parentTitle = parent?.title, !parentTitle.isEmpty {
            return "\(parentTitle): \(title)"
        }
        return title
    }

    func nextRecurrenceInstance(now: Date = .now, calendar: Calendar = Calendar(identifier: .gregorian)) -> FocusTask? {
        guard recurrence != .none else { return nil }
        let nextDue = shifted(date: dueDate, calendar: calendar)
        guard let nextDue else { return nil }
        return FocusTask(
            title: title,
            notes: notes,
            dueDate: nextDue,
            isCompleted: false,
            completedAt: nil,
            recurrence: recurrence,
            recurrenceIntervalDays: recurrenceIntervalDays,
            recurrenceWeekdays: recurrenceWeekdays,
            createdAt: now,
            updatedAt: now,
            project: project,
            parent: parent
        )
    }

    private func shifted(date: Date?, calendar: Calendar) -> Date? {
        guard let date else { return nil }
        switch recurrence {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return nextWeeklyDate(from: date, calendar: calendar)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .custom:
            guard let days = recurrenceIntervalDays, days >= 1 else { return nil }
            return calendar.date(byAdding: .day, value: days, to: date)
        }
    }

    private func nextWeeklyDate(from date: Date, calendar: Calendar) -> Date? {
        let weekdaySet = Set(recurrenceWeekdays ?? [])
        guard !weekdaySet.isEmpty else {
            return calendar.date(byAdding: .day, value: 7, to: date)
        }
        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let candidateWeekday = calendar.component(.weekday, from: candidate)
            if weekdaySet.contains(candidateWeekday) {
                return candidate
            }
        }
        return calendar.date(byAdding: .day, value: 7, to: date)
    }
}
