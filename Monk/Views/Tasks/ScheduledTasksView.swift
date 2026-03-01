import SwiftData
import SwiftUI
import UIKit

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
    @State private var recentlyCompletedTaskIDs: Set<UUID> = []
    @State private var completionBufferTasks: [UUID: Task<Void, Never>] = [:]
    @State private var inlineComposerDay: Date?
    @State private var inlineComposerText: String = ""
    @State private var inlineComposerHasKeyboardFocus = false

    @Binding var selectedTaskID: UUID?
    let onAdd: () -> Void
    let onEdit: (FocusTask) -> Void
    var showsHeader: Bool = true
    var hiddenTaskIDs: Set<UUID> = []
    var tutorialTargetTaskID: UUID? = nil

    private var sections: [ScheduledTaskSection] {
        let taskEntries = entries(for: allTasks)
        let grouped = Dictionary(grouping: taskEntries) { $0.day }
        var visibleDays = Set(grouped.keys)
        let today = calendar.startOfDay(for: Date())

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            visibleDays.insert(day)
        }

        return visibleDays.sorted().map { day in
            let items = (grouped[day] ?? []).sorted(by: entrySort)
            return ScheduledTaskSection(id: day, date: day, entries: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                header
            }

            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            dayHeader(for: section.date)

                            VStack(spacing: 2) {
                                ForEach(section.entries) { entry in
                                    taskRow(for: entry, in: section)
                                }
                            }

                            if inlineComposerDay == section.date {
                                inlineComposer(for: section.date)
                            }

                            if section.id != sections.last?.id {
                                daySeparator
                            }
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 0)
        .background(Color.clear)
        .onAppear {
            Haptics.primeTaskCompletion()
        }
        .onChange(of: showCompleted) { _, enabled in
            if enabled {
                clearAllCompletionBuffers()
            }
        }
        .onDisappear {
            cancelInlineComposer()
            clearAllCompletionBuffers()
        }
    }
}

private extension ScheduledTasksView {
    var headerTitle: String {
        "Tasks"
    }

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
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(Color.white.opacity(0.2))
            .foregroundStyle(.white)
            Button(action: {
                Haptics.heavy()
                onAdd()
            }) {
                Label("New task", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .tint(Color.white.opacity(0.2))
            .foregroundStyle(.white)
            .guidedTutorialAnchor(.homeNewTaskButton)
        }
        .foregroundStyle(.white)
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

    func dayHeader(for date: Date) -> some View {
        Button {
            beginInlineComposer(for: date)
        } label: {
            HStack(spacing: 0) {
                Text(sectionDisplay(date))
                    .font(calendar.isDateInToday(date) ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(calendar.isDateInToday(date) ? .white : .white.opacity(0.75))
                Spacer()
            }
            .padding(.top, 2)
            .padding(.bottom, 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func inlineComposer(for day: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .stroke(Color.white.opacity(0.75), lineWidth: 2)
                .frame(width: 20, height: 20)

            InlineReturnTextField(
                text: $inlineComposerText,
                isFirstResponder: $inlineComposerHasKeyboardFocus,
                placeholder: "New task",
                onReturn: {
                    createInlineTask(for: day)
                },
                onFocusChange: { isFocused in
                    if !isFocused && inlineComposerDay == day {
                        cancelInlineComposer()
                    }
                }
            )
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            inlineComposerHasKeyboardFocus = true
        }
    }

    var daySeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .padding(.top, 4)
    }

    var emptyState: some View {
        ContentUnavailableView {
            Label("No scheduled tasks yet.", systemImage: "checklist")
                .font(.headline.weight(.semibold))
        } description: {
            Text("Create a task with a due date to see it here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
        } actions: {
            Button(action: {
                Haptics.heavy()
                onAdd()
            }) {
                Label("New Task", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .tint(Color.white.opacity(0.24))
            .foregroundStyle(.white)
            .guidedTutorialAnchor(.homeEmptyNewTaskButton)
        }
        .padding(12)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    func taskRow(for entry: ScheduledTaskEntry, in section: ScheduledTaskSection) -> some View {
        let baseRow = ScheduledTaskRow(
            entry: entry,
            isDimmed: selectedTaskID != nil && selectedTaskID != entry.task.id,
            onTap: { toggleSelection(for: entry.task) },
            onEdit: { onEdit(entry.task) },
            onDelete: { deleteTask(entry.task) },
            onToggleCompletion: { toggleCompletion(for: entry.task) }
        )

        if let tutorialTargetTaskID, entry.task.id == tutorialTargetTaskID {
            baseRow
                .guidedTutorialAnchor(.homeTaskRow(tutorialTargetTaskID))
        } else if isPrimaryTutorialTask(entry, section: section) {
            baseRow
                .guidedTutorialAnchor(.homeTaskRow(entry.task.id))
        } else {
            baseRow
        }
    }

    func isPrimaryTutorialTask(_ entry: ScheduledTaskEntry, section: ScheduledTaskSection) -> Bool {
        guard let firstSection = sections.first else { return false }
        guard section.id == firstSection.id else { return false }
        return section.entries.first?.id == entry.id
    }

    func entries(for tasks: [FocusTask]) -> [ScheduledTaskEntry] {
        tasks.compactMap { task in
            guard !hiddenTaskIDs.contains(task.id) else { return nil }
            guard let due = task.dueDate else { return nil }
            guard showCompleted || !task.isCompleted || recentlyCompletedTaskIDs.contains(task.id) else { return nil }
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
        let wasCompleted = task.isCompleted
        var noAnimationTransaction = Transaction(animation: nil)
        noAnimationTransaction.disablesAnimations = true
        withTransaction(noAnimationTransaction) {
            Haptics.taskCompletion()

            if task.isCompleted {
                task.isCompleted = false
                task.completedAt = nil
            } else {
                task.isCompleted = true
                task.completedAt = now
                if let next = task.nextRecurrenceInstance(now: now, calendar: calendar) {
                    modelContext.insert(next)
                }
            }
            task.updatedAt = now

            if modelContext.saveOrRollback() {
                if wasCompleted {
                    clearCompletionBuffer(for: task.id)
                } else if !showCompleted {
                    startCompletionBuffer(for: task.id)
                }

                if !showCompleted && task.isCompleted && selectedTaskID == task.id {
                    selectedTaskID = nil
                }
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

    func beginInlineComposer(for day: Date) {
        if inlineComposerDay != day {
            inlineComposerText = ""
            inlineComposerDay = day
        }
        inlineComposerHasKeyboardFocus = true
        Haptics.soft()
    }

    func createInlineTask(for day: Date) {
        let titles = inlineComposerText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !titles.isEmpty else {
            cancelInlineComposer()
            return
        }

        let now = Date()
        let dayStart = calendar.startOfDay(for: day)
        var dueCursor = nextDueDate(for: day)

        for title in titles {
            let task = FocusTask(
                title: title,
                dueDate: dueCursor,
                isCompleted: false,
                completedAt: nil,
                recurrence: .none,
                recurrenceIntervalDays: nil,
                recurrenceWeekdays: nil,
                createdAt: now,
                updatedAt: now,
                project: nil
            )
            modelContext.insert(task)
            dueCursor = incrementDueDate(from: dueCursor, dayStart: dayStart)
        }

        if modelContext.saveOrRollback() {
            inlineComposerText = ""
            inlineComposerDay = day
            inlineComposerHasKeyboardFocus = true
            Haptics.success()
        }
    }

    func cancelInlineComposer() {
        inlineComposerDay = nil
        inlineComposerText = ""
        inlineComposerHasKeyboardFocus = false
    }

    func deleteTask(_ task: FocusTask) {
        clearCompletionBuffer(for: task.id)
        if selectedTaskID == task.id {
            selectedTaskID = nil
        }
        modelContext.delete(task)
        _ = modelContext.saveOrRollback()
    }

    func nextDueDate(for day: Date) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        let baseDefault = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        let latestDueOnDay = allTasks
            .compactMap(\.dueDate)
            .filter { calendar.isDate($0, inSameDayAs: dayStart) }
            .max()
        let base = latestDueOnDay ?? baseDefault
        let incremented = calendar.date(byAdding: .minute, value: 1, to: base) ?? base
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return incremented }
        let latestAllowed = calendar.date(byAdding: .second, value: -1, to: nextDay) ?? incremented
        return min(incremented, latestAllowed)
    }

    func incrementDueDate(from base: Date, dayStart: Date) -> Date {
        let incremented = calendar.date(byAdding: .minute, value: 1, to: base) ?? base
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return incremented }
        let latestAllowed = calendar.date(byAdding: .second, value: -1, to: nextDay) ?? incremented
        return min(incremented, latestAllowed)
    }
}

private struct InlineReturnTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    let placeholder: String
    let onReturn: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.textColor = .white
        textField.tintColor = .white
        textField.returnKeyType = .default
        textField.autocapitalizationType = .sentences
        textField.autocorrectionType = .yes
        textField.spellCheckingType = .yes
        textField.clearButtonMode = .never
        textField.adjustsFontForContentSizeCategory = true
        textField.font = UIFont.preferredFont(forTextStyle: .body).withWeight(.semibold)
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        )
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }

        if isFirstResponder && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !isFirstResponder && uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: InlineReturnTextField

        init(parent: InlineReturnTextField) {
            self.parent = parent
        }

        @objc
        func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFirstResponder {
                parent.isFirstResponder = true
            }
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isFirstResponder {
                parent.isFirstResponder = false
            }
            parent.onFocusChange(false)
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits) as UIFontDescriptor? else {
            return self
        }
        return UIFont.systemFont(ofSize: descriptor.pointSize, weight: weight)
    }
}
