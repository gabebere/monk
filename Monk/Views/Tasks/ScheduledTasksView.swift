import SwiftData
import SwiftUI

struct ScheduledTaskEntry: Identifiable {
    let id: String
    let task: FocusTask
    let originalDate: Date

    init(task: FocusTask, date: Date) {
        self.task = task
        self.originalDate = date
        self.id = "\(task.id.uuidString)-due-\(Int(date.timeIntervalSince1970))"
    }
}

struct ScheduledTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(RemindersSyncKeys.enabled) private var remindersSyncEnabled = false
    @AppStorage(RemindersSyncKeys.destinationListIdentifier) private var remindersSyncDestinationListIdentifier: String = ""
    @Query(sort: [SortDescriptor(\FocusTask.updatedAt, order: .reverse)]) private var allTasks: [FocusTask]
    @State private var recentlyCompletedTaskIDs: Set<UUID> = []
    @State private var completionBufferTasks: [UUID: Task<Void, Never>] = [:]

    var showsHeader: Bool = true
    var hiddenTaskIDs: Set<UUID> = []
    var tutorialTargetTaskID: UUID? = nil
    let onStartTask: (FocusTask) -> Void

    private let maxVisibleEntries = 6

    private var upcomingEntries: [ScheduledTaskEntry] {
        Array(entries(for: allTasks).sorted(by: entrySort).prefix(maxVisibleEntries))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                header
            }

            if upcomingEntries.isEmpty {
                GeometryReader { proxy in
                    VStack {
                        Spacer(minLength: 0)
                        emptyState
                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(upcomingEntries) { entry in
                        taskRow(for: entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 0)
        .background(Color.clear)
        .onAppear {
            Haptics.primeTaskCompletion()
        }
        .onDisappear {
            clearAllCompletionBuffers()
        }
    }
}

private extension ScheduledTasksView {
    var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("To-do's")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Scheduled reminders from Apple Reminders")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
        }
    }

    @ViewBuilder
    func taskRow(for entry: ScheduledTaskEntry) -> some View {
        let row = ScheduledTaskRow(
            entry: entry,
            onStart: { onStartTask(entry.task) },
            onToggleCompletion: { toggleCompletion(for: entry.task) }
        )

        if let tutorialTargetTaskID, entry.task.id == tutorialTargetTaskID {
            row.guidedTutorialAnchor(.homeTaskRow(tutorialTargetTaskID))
        } else {
            row
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            Text(emptyStateTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(emptyStateDescription)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var emptyStateTitle: String {
        remindersSyncEnabled ? "You're all caught up! ;)" : "Apple Reminders is off."
    }

    var emptyStateDescription: String {
        if remindersSyncEnabled {
            return "Add a reminder in Apple Reminders and it will appear here."
        }
        return "Turn on Apple Reminders in Settings to show scheduled reminders in Monk."
    }

    func entries(for tasks: [FocusTask]) -> [ScheduledTaskEntry] {
        guard remindersSyncEnabled else { return [] }

        return tasks.compactMap { task in
            guard !hiddenTaskIDs.contains(task.id) else { return nil }
            guard task.isScheduled, task.isReminderBacked, let due = task.dueDate else { return nil }
            guard !task.isCompleted || recentlyCompletedTaskIDs.contains(task.id) else { return nil }
            return ScheduledTaskEntry(task: task, date: due)
        }
    }

    func entrySort(lhs: ScheduledTaskEntry, rhs: ScheduledTaskEntry) -> Bool {
        if lhs.originalDate != rhs.originalDate {
            return lhs.originalDate < rhs.originalDate
        }
        return lhs.task.displayTitle.localizedCaseInsensitiveCompare(rhs.task.displayTitle) == .orderedAscending
    }

    func toggleCompletion(for task: FocusTask) {
        let now = Date()
        let wasCompleted = task.isCompleted
        var noAnimationTransaction = Transaction(animation: nil)
        noAnimationTransaction.disablesAnimations = true

        withTransaction(noAnimationTransaction) {
            Haptics.taskCompletion()

            if wasCompleted {
                task.isCompleted = false
                task.completedAt = nil
                clearCompletionBuffer(for: task.id)
            } else {
                task.isCompleted = true
                task.completedAt = now
                startCompletionBuffer(for: task.id)
            }
            task.updatedAt = now

            if modelContext.saveOrRollback() {
                syncTaskWithReminders(task)
            } else if !wasCompleted {
                clearCompletionBuffer(for: task.id)
            }
        }
    }

    func startCompletionBuffer(for taskID: UUID) {
        clearCompletionBuffer(for: taskID)
        recentlyCompletedTaskIDs.insert(taskID)
        completionBufferTasks[taskID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            recentlyCompletedTaskIDs.remove(taskID)
            completionBufferTasks[taskID] = nil
        }
    }

    func clearCompletionBuffer(for taskID: UUID) {
        completionBufferTasks[taskID]?.cancel()
        completionBufferTasks[taskID] = nil
        recentlyCompletedTaskIDs.remove(taskID)
    }

    func clearAllCompletionBuffers() {
        completionBufferTasks.values.forEach { $0.cancel() }
        completionBufferTasks.removeAll()
        recentlyCompletedTaskIDs.removeAll()
    }

    func syncTaskWithReminders(_ task: FocusTask) {
        guard remindersSyncEnabled else { return }
        Task { @MainActor in
            await RemindersSyncService.shared.upsertReminder(
                for: task,
                modelContext: modelContext,
                destinationListIdentifier: normalizedRemindersDestinationListIdentifier
            )
        }
    }

    var normalizedRemindersDestinationListIdentifier: String? {
        RemindersSyncStorage.normalizedIdentifier(remindersSyncDestinationListIdentifier)
    }
}
