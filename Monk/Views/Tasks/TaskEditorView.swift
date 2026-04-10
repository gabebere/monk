import SwiftData
import SwiftUI

enum TaskEditorMode {
    case create(defaultProject: Project?)
    case edit(task: FocusTask)
}

struct TaskEditorRoute: Identifiable, Equatable {
    let id: UUID
    let mode: TaskEditorMode

    static func create(defaultProject: Project? = nil) -> TaskEditorRoute {
        TaskEditorRoute(id: UUID(), mode: .create(defaultProject: defaultProject))
    }

    static func edit(_ task: FocusTask) -> TaskEditorRoute {
        TaskEditorRoute(id: task.id, mode: .edit(task: task))
    }

    static func == (lhs: TaskEditorRoute, rhs: TaskEditorRoute) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ProjectOption: Identifiable, Hashable {
    let id: UUID
    let title: String
}

private struct ParentTaskOption: Identifiable, Hashable {
    let id: UUID
    let title: String
}

struct TaskEditorView: View {
    let mode: TaskEditorMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @AppStorage(RemindersSyncKeys.enabled) private var remindersSyncEnabled = false
    @AppStorage(RemindersSyncKeys.destinationListIdentifier) private var remindersSyncDestinationListIdentifier: String = ""

    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var recurrence: TaskRecurrence
    @State private var customInterval: Int
    @State private var selectedProjectID: UUID?
    @State private var selectedParentTaskID: UUID?
    @State private var selectedWeekdays: Set<Int>
    @State private var projectOptions: [ProjectOption] = []
    @State private var parentTaskOptions: [ParentTaskOption] = []
    @State private var isProjectSelectorPresented = false
    @State private var isParentTaskSelectorPresented = false
    @State private var validationMessage: String?

    init(mode: TaskEditorMode) {
        self.mode = mode
        switch mode {
        case .create(let defaultProject):
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _dueDate = State(initialValue: TaskEditorView.calendarAdjustedNow())
            _recurrence = State(initialValue: .none)
            _customInterval = State(initialValue: 1)
            _selectedProjectID = State(initialValue: defaultProject?.id)
            _selectedParentTaskID = State(initialValue: nil)
            _selectedWeekdays = State(initialValue: [])
        case .edit(let task):
            _title = State(initialValue: task.title)
            _notes = State(initialValue: task.notes ?? "")
            _dueDate = State(initialValue: task.dueDate ?? TaskEditorView.calendarAdjustedNow())
            _recurrence = State(initialValue: task.recurrence)
            _customInterval = State(initialValue: max(task.recurrenceIntervalDays ?? 1, 1))
            _selectedProjectID = State(initialValue: task.project?.id)
            _selectedParentTaskID = State(initialValue: task.parent?.id)
            _selectedWeekdays = State(initialValue: Set(task.recurrenceWeekdays ?? []))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: sectionHeader("Details")) {
                    VStack(spacing: 12) {
                        inputRow {
                            TextField("Title", text: $title)
                                .textInputAutocapitalization(.sentences)
                                .foregroundColor(.white)
                        }

                        inputRow {
                            TextField("Notes (optional)", text: $notes, axis: .vertical)
                                .textInputAutocapitalization(.sentences)
                                .foregroundColor(.white)
                        }

                        inputRow {
                            Button {
                                loadProjectsIfNeeded(force: true)
                                isProjectSelectorPresented = true
                            } label: {
                                HStack {
                                    Text("Project")
                                    Spacer()
                                    Text(selectedProjectTitle)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        inputRow {
                            Button {
                                loadParentTasksIfNeeded(force: true)
                                isParentTaskSelectorPresented = true
                            } label: {
                                HStack {
                                    Text("Parent task")
                                    Spacer()
                                    Text(selectedParentTaskTitle)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .sectionCard()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section(header: sectionHeader("Dates")) {
                    VStack(spacing: 12) {
                        inputRow {
                            DatePicker("Due date", selection: $dueDate, displayedComponents: [.date])
                                .foregroundColor(.white)
                        }
                    }
                    .sectionCard()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section(header: sectionHeader("Recurrence")) {
                    VStack(spacing: 12) {
                        Picker("Recurrence", selection: $recurrence) {
                            ForEach(TaskRecurrence.allCases, id: \.self) { recurrence in
                                Text(recurrence.displayName).tag(recurrence)
                            }
                        }
                        .pickerStyle(.segmented)

                        if recurrence == .custom {
                            inputRow {
                                Picker("Every", selection: $customInterval) {
                                    ForEach(1...365, id: \.self) { value in
                                        Text("\(value) day\(value == 1 ? "" : "s")").tag(value)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 120)
                            }
                        } else if recurrence == .weekly {
                            WeekdayPicker(selectedWeekdays: $selectedWeekdays)
                        }
                    }
                    .sectionCard()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if let validationMessage {
                    Section {
                        VStack {
                            Text(validationMessage)
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .sectionCard()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if case .edit(let task) = mode {
                    Section {
                        Button(role: .destructive) {
                            delete(task: task)
                        } label: {
                            Text("Delete Task")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .sectionCard()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(pageBackground.ignoresSafeArea())
            .listSectionSpacing(12)
            .tint(controlTint)
            .navigationTitle(modeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.soft()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadProjectsIfNeeded()
                loadParentTasksIfNeeded()
            }
            .sheet(isPresented: $isProjectSelectorPresented) {
                NavigationStack {
                    ZStack {
                        sheetBackground
                        ScrollView {
                            VStack(spacing: 12) {
                                projectRow(title: "None", isSelected: selectedProjectID == nil) {
                                    selectedProjectID = nil
                                    isProjectSelectorPresented = false
                                }

                                ForEach(projectOptions) { option in
                                    projectRow(title: option.title, isSelected: selectedProjectID == option.id) {
                                        selectedProjectID = option.id
                                        isProjectSelectorPresented = false
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                    }
                    .navigationTitle("Project")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isProjectSelectorPresented = false }
                        }
                    }
                    .onAppear {
                        loadProjectsIfNeeded()
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isParentTaskSelectorPresented) {
                NavigationStack {
                    ZStack {
                        sheetBackground
                        ScrollView {
                            VStack(spacing: 12) {
                                projectRow(title: "None", isSelected: selectedParentTaskID == nil) {
                                    selectedParentTaskID = nil
                                    isParentTaskSelectorPresented = false
                                }

                                ForEach(parentTaskOptions) { option in
                                    projectRow(title: option.title, isSelected: selectedParentTaskID == option.id) {
                                        selectedParentTaskID = option.id
                                        isParentTaskSelectorPresented = false
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                    }
                    .navigationTitle("Parent Task")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isParentTaskSelectorPresented = false }
                        }
                    }
                    .onAppear {
                        loadParentTasksIfNeeded(force: true)
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

private extension TaskEditorView {
    var modeTitle: String {
        switch mode {
        case .create: return "New Task"
        case .edit: return "Edit Task"
        }
    }

    var selectedProjectTitle: String {
        if let id = selectedProjectID, let match = projectOptions.first(where: { $0.id == id }) {
            return match.title
        }
        return "None"
    }

    var selectedParentTaskTitle: String {
        if let id = selectedParentTaskID,
           let match = parentTaskOptions.first(where: { $0.id == id }) {
            return match.title
        }
        if let id = selectedParentTaskID,
           let match = fetchTask(with: id) {
            return match.displayTitle
        }
        return "None"
    }

    var controlTint: Color {
        Color(red: 0.20, green: 0.55, blue: 0.96)
    }

    var pageBackground: Color {
        Color(red: 0.07, green: 0.07, blue: 0.08)
    }

    var cardBackground: Color {
        Color(red: 0.13, green: 0.14, blue: 0.16)
    }

    var cardStroke: Color {
        Color.white.opacity(0.08)
    }

    func selectedProject(defaultProject: Project?) -> Project? {
        if let projectID = selectedProjectID {
            return fetchProject(with: projectID)
        }
        if case .create(let defaultProject) = mode {
            return defaultProject
        }
        return nil
    }

    func selectedParentTask() -> FocusTask? {
        guard let parentTaskID = selectedParentTaskID else { return nil }
        return fetchTask(with: parentTaskID)
    }

    func save() {
        validationMessage = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "Title cannot be empty."
            return
        }
        if recurrence == .custom && customInterval < 1 {
            validationMessage = "Custom recurrence must be at least 1 day."
            return
        }
        if recurrence == .weekly && selectedWeekdays.isEmpty {
            validationMessage = "Choose at least one weekday for weekly recurrence."
            return
        }

        let now = Date()
        let intervalDays = recurrence == .custom ? customInterval : nil
        let weekdays = recurrence == .weekly ? Array(selectedWeekdays).sorted() : nil
        let taskProject = selectedProject(defaultProject: nil)
        let parentTask = selectedParentTask()
        if case .edit(let rtask) = mode,
           let parentTask,
           disallowedParentTaskIDs().contains(parentTask.id) {
            validationMessage = "Choose a different parent task."
            return
        }
        var tasksToSync: [FocusTask] = []

        switch mode {
        case .create(let defaultProject):
            let project = taskProject ?? defaultProject 
            let newTask = FocusTask(
                title: trimmedTitle,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                dueDate: dueDate,
                isCompleted: false,
                completedAt: nil,
                recurrence: recurrence,
                recurrenceIntervalDays: intervalDays,
                recurrenceWeekdays: weekdays,
                createdAt: now,
                updatedAt: now,
                project: project,
                parent: parentTask
            )
            modelContext.insert(newTask)
            tasksToSync = [newTask]
        case .edit(let task):
            task.title = trimmedTitle
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            task.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            task.dueDate = dueDate
            task.recurrence = recurrence
            task.recurrenceIntervalDays = intervalDays
            task.recurrenceWeekdays = weekdays
            task.project = taskProject
            task.parent = parentTask
            task.updatedAt = now
            tasksToSync = [task]
        }

        if modelContext.saveOrRollback() {
            if remindersSyncEnabled {
                Task { @MainActor in
                    for task in tasksToSync {
                        await RemindersSyncService.shared.upsertReminder(
                            for: task,
                            modelContext: modelContext,
                            destinationListIdentifier: normalizedRemindersDestinationListIdentifier
                        )
                    }
                }
            }
            Haptics.success()
            dismiss()
        } else {
            validationMessage = "Could not save changes. Please try again."
        }
    }

    func delete(task: FocusTask) {
        if remindersSyncEnabled {
            let reminderTargets = task.taskTree.map {
                (
                    taskID: $0.id,
                    calendarItemIdentifier: $0.reminderCalendarItemIdentifier,
                    externalIdentifier: $0.reminderExternalIdentifier
                )
            }
            Task { @MainActor in
                for target in reminderTargets {
                    await RemindersSyncService.shared.deleteReminder(
                        taskID: target.taskID,
                        calendarItemIdentifier: target.calendarItemIdentifier,
                        externalIdentifier: target.externalIdentifier
                    )
                }
            }
        }
        modelContext.delete(task)
        if modelContext.saveOrRollback() {
            Haptics.success()
            dismiss()
        } else {
            validationMessage = "Could not delete task. Please try again."
        }
    }

    var normalizedRemindersDestinationListIdentifier: String? {
        RemindersSyncStorage.normalizedIdentifier(remindersSyncDestinationListIdentifier)
    }
}

private extension TaskEditorView {
    static func calendarAdjustedNow() -> Date {
        Calendar(identifier: .gregorian).startOfDay(for: Date())
    }

    func loadProjectsIfNeeded(force: Bool = false) {
        guard projectOptions.isEmpty || force else { return }
        let descriptor = FetchDescriptor<Project>()
        do {
            let projects = try modelContext.fetch(descriptor).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            projectOptions = projects.map { ProjectOption(id: $0.id, title: $0.title) }
        } catch {
            projectOptions = []
        }
    }

    func fetchProject(with id: UUID) -> Project? {
        var descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == id
            }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func loadParentTasksIfNeeded(force: Bool = false) {
        guard parentTaskOptions.isEmpty || force else { return }
        let descriptor = FetchDescriptor<FocusTask>()
        let disallowedIDs = disallowedParentTaskIDs()

        do {
            let tasks = try modelContext.fetch(descriptor)
                .filter { !disallowedIDs.contains($0.id) }
                .sorted { lhs, rhs in
                    lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }

            parentTaskOptions = tasks.map { task in
                ParentTaskOption(id: task.id, title: task.displayTitle)
            }
        } catch {
            parentTaskOptions = []
        }
    }

    func disallowedParentTaskIDs() -> Set<UUID> {
        guard case .edit(let task) = mode else { return [] }
        return Set([task.id] + descendantTaskIDs(of: task))
    }

    func descendantTaskIDs(of task: FocusTask) -> [UUID] {
        task.subtasksUnwrapped.flatMap { child in
            [child.id] + descendantTaskIDs(of: child)
        }
    }

    func fetchTask(with id: UUID) -> FocusTask? {
        var descriptor = FetchDescriptor<FocusTask>(
            predicate: #Predicate { task in
                task.id == id
            }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    var sheetBackground: some View {
        Color(red: 0.07, green: 0.07, blue: 0.08)
            .ignoresSafeArea()
    }

    func projectRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(controlTint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(cardStroke.opacity(isSelected ? 0.6 : 0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    func inputRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func sectionCard() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.13, green: 0.14, blue: 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}
