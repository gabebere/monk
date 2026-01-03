import SwiftData
import SwiftUI

struct ScheduledTaskEntry: Identifiable {
    let id: String
    let task: FocusTask
    let day: Date
    let originalDate: Date

    init(task: FocusTask, date: Date, calendar: Calendar) {
        self.task = task
        self.originalDate = date
        self.day = calendar.startOfDay(for: date)
        self.id = "\(task.id.uuidString)-due-\(Int(date.timeIntervalSince1970))"
    }
}

struct ScheduledTaskSection: Identifiable {
    let id: Date
    let date: Date
    let entries: [ScheduledTaskEntry]
}

struct ScheduledTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @AppStorage("tasks.showCompleted") private var showCompleted = false
    @Query(sort: [SortDescriptor(\FocusTask.updatedAt, order: .reverse)]) private var allTasks: [FocusTask]

    @Binding var selectedTaskID: UUID?
    let onAdd: () -> Void
    let onEdit: (FocusTask) -> Void

    private var sections: [ScheduledTaskSection] {
        let taskEntries = entries(for: allTasks)
        let grouped = Dictionary(grouping: taskEntries) { $0.day }
        return grouped.keys.sorted().map { day in
            let items = (grouped[day] ?? []).sorted(by: entrySort)
            return ScheduledTaskSection(id: day, date: day, entries: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            if !isFirstSection(section) {
                                Text(sectionDisplay(section.date))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            VStack(spacing: 8) {
                                ForEach(section.entries) { entry in
                                    ScheduledTaskRow(
                                        entry: entry,
                                        isSelected: selectedTaskID == entry.task.id,
                                        isDimmed: selectedTaskID != nil && selectedTaskID != entry.task.id,
                                        onEdit: { onEdit(entry.task) },
                                        onToggleCompletion: { toggleCompletion(for: entry.task) }
                                    )
                                    .onTapGesture {
                                        toggleSelection(for: entry.task)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .background(Color.clear)
    }
}

private extension ScheduledTasksView {
    var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            Button(action: {
                Haptics.heavy()
                withAnimation(.none) {
                    showCompleted.toggle()
                }
            }) {
                Text(showCompleted ? "Hide" : "Show all")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button(action: {
                Haptics.heavy()
                onAdd()
            }) {
                Label("New task", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.iconOnly)
                    .padding(8)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    var headerTitle: String {
        if let firstDate = sections.first?.date {
            if calendar.isDateInToday(firstDate) {
                return "Today"
            }
            if calendar.isDateInTomorrow(firstDate) {
                return "Tomorrow"
            }
            if calendar.isDateInYesterday(firstDate) {
                return "Yesterday"
            }
            return firstDate.formatted(.dateTime.weekday(.wide).month().day())
        }
        return "Tasks"
    }

    func sectionDisplay(_ date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month().day())
    }

    func isFirstSection(_ section: ScheduledTaskSection) -> Bool {
        guard let first = sections.first else { return false }
        return first.id == section.id
    }

    var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No scheduled tasks yet.")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Create a task with a due date to see it here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
            Button(action: {
                Haptics.heavy()
                onAdd()
            }) {
                Label("New Task", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .foregroundStyle(.white)
    }

    func entries(for tasks: [FocusTask]) -> [ScheduledTaskEntry] {
        tasks.compactMap { task in
            guard let due = task.dueDate else { return nil }
            guard showCompleted || !task.isCompleted else { return nil }
            return ScheduledTaskEntry(task: task, date: due, calendar: calendar)
        }
    }

    func entrySort(lhs: ScheduledTaskEntry, rhs: ScheduledTaskEntry) -> Bool {
        if lhs.day != rhs.day {
            return lhs.day < rhs.day
        }
        if lhs.originalDate != rhs.originalDate {
            return lhs.originalDate < rhs.originalDate
        }
        return lhs.task.displayTitle < rhs.task.displayTitle
    }

    func toggleSelection(for task: FocusTask) {
        if selectedTaskID == task.id {
            selectedTaskID = nil
        } else {
            selectedTaskID = task.id
        }
        Haptics.soft()
    }

    func toggleCompletion(for task: FocusTask) {
        let now = Date()
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
        } else {
            task.isCompleted = true
            task.completedAt = now
            if let next = task.nextRecurrenceInstance(now: now, calendar: calendar) {
                modelContext.insert(next)
            }
            Haptics.success()
        }
        task.updatedAt = now

        if modelContext.saveOrRollback() {
            if !showCompleted && task.isCompleted && selectedTaskID == task.id {
                selectedTaskID = nil
            }
        }
    }
}
