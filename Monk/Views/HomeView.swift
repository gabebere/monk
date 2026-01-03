import SwiftUI
import SwiftData
import FamilyControls
import UIKit

struct HomeView: View {
    @EnvironmentObject private var focus: FocusManager
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsList: [Preferences]
    @Query(sort: [SortDescriptor(\FocusTask.updatedAt, order: .reverse)]) private var focusTasks: [FocusTask]
    @State private var taskEditorRoute: TaskEditorRoute?
    @State private var selectedTaskID: UUID?

    private var prefs: Preferences {
        if let existing = prefsList.first { return existing }
        let created = Preferences(hasConvertedDailyGoal: true)
        modelContext.insert(created)
        return created
    }

    private var selectedTask: FocusTask? {
        focusTasks.first(where: { $0.id == selectedTaskID })
    }

    var body: some View {
        ZStack(alignment: .top) {
            AnimatingBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    TimerCard(selectedTask: selectedTask)
                        if FeatureFlags.tasksV1Enabled {
                        ScheduledTasksView(
                            selectedTaskID: $selectedTaskID,
                            onAdd: { taskEditorRoute = .create(defaultProject: nil) },
                            onEdit: { task in taskEditorRoute = .edit(task) }
                        )
                        .padding(.top, 32)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal)
                .padding(.top, 64)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("Welcome to Monk.")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $taskEditorRoute) { route in
            switch route.mode {
            case .create(let defaultProject):
                TaskEditorView(mode: .create(defaultProject: defaultProject))
            case .edit(let task):
                TaskEditorView(mode: .edit(task: task))
            }
        }
    }
}
private struct TimerCard: View {
    @EnvironmentObject private var focus: FocusManager
    @EnvironmentObject private var revenueCat: RevenueCatService
    @EnvironmentObject private var entitlementSync: EntitlementSyncService
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsList: [Preferences]
    let selectedTask: FocusTask?

    @State private var outerAngle: Double = -30
    @State private var innerAngle: Double = 30
    @State private var driftX: CGFloat = 0
    @State private var driftY: CGFloat = 0
    @Namespace private var focusAnim
    @State private var rippleOpacity: Double = 0
    @State private var rippleScale: CGFloat = 1
    @State private var pressDown: Bool = false
    @State private var outerLoopTask: Task<Void, Never>? = nil
    @State private var innerLoopTask: Task<Void, Never>? = nil
    @State private var showStopDetails: Bool = false
    @State private var stoppedSession: FocusSession? = nil
    @State private var showingProjectPicker: Bool = false
    @State private var showingPaywall = false

    var body: some View {
        VStack(spacing: 20) {
            if focus.currentSession == nil {
                Button(action: {
                    Haptics.heavy()
                    handlePrimaryTap()
                }) {
                    ZStack {
                        Capsule()
                            .fill(Theme.buttonGradient)
                            .opacity(rippleOpacity)
                            .scaleEffect(rippleScale)
                            .blur(radius: 20)
                            .animation(.easeOut(duration: 0.6), value: rippleOpacity)
                            .animation(.easeOut(duration: 0.6), value: rippleScale)

                        let cyanShadowRadius: CGFloat = 36
                        let blueShadowRadius: CGFloat = 54

                        Text("Time to focus?")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .background(
                                Capsule().fill(Theme.buttonGradient)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                    .blendMode(.overlay)
                            )
                            .shadow(color: Color.cyan.opacity(0.5), radius: cyanShadowRadius, x: 0, y: 10)
                            .shadow(color: Color.blue.opacity(0.35), radius: blueShadowRadius, x: 0, y: 0)
                            .scaleEffect(pressDown ? 0.96 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: pressDown)
                    }
                }
                .accessibilityLabel("Start focusing")
                .background(
                    ZStack {
                        Ellipse()
                            .fill(AngularGradient(colors: [
                                Color.cyan.opacity(0.8),
                                Color.blue.opacity(0.7),
                                Color.purple.opacity(0.75),
                                Color.cyan.opacity(0.8)
                            ], center: .center))
                            .frame(width: 180, height: 120)
                            .blur(radius: 16)
                            .rotationEffect(.degrees(outerAngle))
                            .opacity(0.7)
                            .offset(x: driftX, y: driftY)
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)

                        Ellipse()
                            .fill(AngularGradient(colors: [
                                Color.purple.opacity(0.9),
                                Color.blue.opacity(0.75),
                                Color.cyan.opacity(0.85),
                                Color.purple.opacity(0.9)
                            ], center: .center))
                            .frame(width: 150, height: 100)
                            .blur(radius: 10)
                            .rotationEffect(.degrees(innerAngle))
                            .opacity(0.8)
                            .offset(x: -driftX * 0.83, y: -driftY * 0.75)
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                )
                .padding(.top, 0)
                .transition(.focusElegant)
            } else {
                VStack(spacing: 12) {
                    Text(elapsedString())
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .kerning(0.5)
                        .foregroundColor(Theme.textPrimary)
                        .accessibilityLabel("Elapsed time")

                    ZStack {
                        Circle()
                            .fill(Theme.buttonGradient)
                            .frame(width: 110, height: 110)
                            .blur(radius: 20)
                            .opacity(0.5)

                        Button(action: {
                            Haptics.heavy()
                            stopSession()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Theme.buttonGradient)
                                    .frame(width: 92, height: 92)
                                    .shadow(color: Color.cyan.opacity(0.45), radius: 22, x: 0, y: 10)
                                    .shadow(color: Color.blue.opacity(0.35), radius: 36, x: 0, y: 0)
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                        }
                        .accessibilityLabel("Stop")
                    }
                    .padding(.bottom, 0)
                }
                .transition(.focusElegant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: focus.currentSession != nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .sheet(isPresented: $showStopDetails) {
            if let session = stoppedSession {
                CompletedSessionView(session: session) {
                    // No-op; stop already occurred
                }
            }
        }
        .sheet(isPresented: $showingProjectPicker) {
            ProjectSelectionSheet { selection in
                startSession(with: selection, task: selectedTask)
            }
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            RevenueCatPaywallView(onClose: {
                showingPaywall = false
            })
                .environmentObject(revenueCat)
        }
        .task {
            if focus.currentSession == nil { restartIdleAnimation() }
        }
        .onChange(of: focus.currentSession == nil) { _, isIdle in
            if isIdle {
                restartIdleAnimation()
            } else {
                outerLoopTask?.cancel(); outerLoopTask = nil
                innerLoopTask?.cancel(); innerLoopTask = nil
            }
        }
    }

    private func startSession(with project: Project?, task: FocusTask?) {
        let sessionID = UUID().uuidString
        let resolvedProject = project ?? task?.project
        focus.start(project: resolvedProject, task: task)
        if let current = focus.currentSession {
            Analytics.track("focus_started", [
                "session_id": current.id.uuidString,
                "project_id": current.project?.id.uuidString ?? "none",
                "task_id": current.task?.id.uuidString ?? task?.id.uuidString ?? "none",
                "ts": Date().timeIntervalSince1970
            ])
        } else {
            Analytics.track("focus_started", [
                "session_id": sessionID,
                "project_id": resolvedProject?.id.uuidString ?? "none",
                "task_id": task?.id.uuidString ?? "none",
                "ts": Date().timeIntervalSince1970
            ])
        }
    }

    private func handlePrimaryTap() {
        // If user is entitled via RevenueCat or synced flag, proceed; otherwise show paywall.
        if revenueCat.isPro || entitlementSync.isEntitled {
            animateStartAndBeginSession()
        } else {
            Analytics.track("paywall_viewed", [
                "offering_id": revenueCat.activeOffering?.identifier ?? "unknown",
                "has_paywall": revenueCat.activeOffering?.paywall != nil,
                "entitlement_active": revenueCat.isPro
            ])
            showingPaywall = true
        }
    }

    private func stopSession() {
        let session = focus.currentSession
        let startTime = session?.startedAt
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            focus.stop()
        }
        if let s = session, let start = startTime {
            let discardShort = prefsList.first?.discardShortSessions == true
            let duration = Date().timeIntervalSince(start)
            let willDiscard = discardShort && duration < 120
            if !willDiscard {
                stoppedSession = s
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showStopDetails = true }
            }
            Analytics.track("focus_stopped", [
                "session_id": s.id.uuidString,
                "project_id": s.project?.id.uuidString ?? "none",
                "task_id": s.task?.id.uuidString ?? "none",
                "duration_sec": duration,
                "ts": Date().timeIntervalSince1970
            ])
        }
    }

    private func animateStartAndBeginSession() {
        guard focus.currentSession == nil else { return }
        pressDown = true
        rippleOpacity = 0.55
        rippleScale = 1.0
        withAnimation(.easeOut(duration: 0.6)) {
            rippleOpacity = 0.0
            rippleScale = 2.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            if let task = selectedTask, let project = task.project {
                startSession(with: project, task: task)
            } else {
                showingProjectPicker = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pressDown = false
            rippleScale = 1.0
        }
    }

    private func elapsedString() -> String {
        guard let start = focus.currentSession?.startedAt else { return "00:00:00" }
        let elapsed = Date().timeIntervalSince(start)
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func restartIdleAnimation() {
        outerLoopTask?.cancel(); outerLoopTask = nil
        innerLoopTask?.cancel(); innerLoopTask = nil
        withAnimation(.none) {
            outerAngle = -30
            innerAngle = 30
        }
        startOuterLoop()
        startInnerLoop()
    }

    private func startOuterLoop() {
        outerLoopTask?.cancel()
        outerLoopTask = Task { @MainActor in
            let seg: UInt64 = 1_200_000_000
            while !Task.isCancelled {
                withAnimation(.linear(duration: 1.2)) { outerAngle = 30 }
                try? await Task.sleep(nanoseconds: seg)
                withAnimation(.linear(duration: 1.2)) { outerAngle = -30 }
                try? await Task.sleep(nanoseconds: seg)
            }
        }
    }

    private func startInnerLoop() {
        innerLoopTask?.cancel()
        innerLoopTask = Task { @MainActor in
            let seg: UInt64 = 1_200_000_000
            while !Task.isCancelled {
                withAnimation(.linear(duration: 1.2)) { innerAngle = -30 }
                try? await Task.sleep(nanoseconds: seg)
                withAnimation(.linear(duration: 1.2)) { innerAngle = 30 }
                try? await Task.sleep(nanoseconds: seg)
            }
        }
    }
}

private struct ProjectSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var focus: FocusManager
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]
    let onSelect: (Project?) -> Void

    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)] }

    private var sortedProjects: [Project] {
        projects.sorted { lhs, rhs in
            let leftDate = focus.lastActivityDate(for: lhs) ?? lhs.createdAt
            let rightDate = focus.lastActivityDate(for: rhs) ?? rhs.createdAt
            return leftDate > rightDate
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.04, blue: 0.10),
                        Color(red: 0.01, green: 0.01, blue: 0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Choose your focus")
                                .font(.title.bold())
                                .foregroundStyle(.white)
                            Text("Apply your next session to a project or keep it unassigned.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        if projects.isEmpty {
                            EmptyProjectsView()
                        } else {
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(sortedProjects) { project in
                                    let gradient = ProjectGradientPalette.gradient(at: project.gradientIndex)
                                    let info = projectProgress(for: project)
                                    ProjectSelectionTile(
                                        title: project.title,
                                        ratioText: info.ratio,
                                        detailText: projectDetail(for: project),
                                        gradient: gradient,
                                        progressFraction: info.fraction
                                    ) {
                                        onSelect(project)
                                        dismiss()
                                    }
                                }
                            }
                        }

                        ProjectSelectionNoProjectTile {
                            onSelect(nil)
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.heavy()
                        dismiss()
                    }
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .presentationDetents([.fraction(0.94), .large])
        .presentationDragIndicator(.visible)
    }

    private func projectProgress(for project: Project) -> (ratio: String, fraction: Double?) {
        let progress = focus.weeklyGoalProgress(for: project)
        if let goal = progress.goalHours, goal > 0 {
            return (String(format: "%.1fh / %.1fh", progress.actualHours, goal), progress.progressFraction)
        } else {
            return (String(format: "%.1fh focused", progress.actualHours), nil)
        }
    }

    private func projectDetail(for project: Project) -> String {
        if let goal = project.weeklyGoalHours, goal > 0 {
            return String(format: "Goal %.0fh/week", goal)
        }
        let hours = focus.totalDuration(for: project) / 3600
        return String(format: "%.1fh logged total", hours)
    }
}

struct ProjectsSection: View {
    @EnvironmentObject private var focus: FocusManager
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]

    let onAdd: () -> Void
    let onInfo: (Project) -> Void

    private var sortedProjects: [Project] {
        projects.sorted { lhs, rhs in
            let leftDate = focus.lastActivityDate(for: lhs) ?? lhs.createdAt
            let rightDate = focus.lastActivityDate(for: rhs) ?? rhs.createdAt
            if leftDate == rightDate { return lhs.createdAt > rhs.createdAt }
            return leftDate > rightDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Projects")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: {
                    Haptics.heavy()
                    onAdd()
                }) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create project")
            }

            if sortedProjects.isEmpty {
                Button(action: {
                    Haptics.heavy()
                    onAdd()
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Create a project to track focus hours")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(.ultraThinMaterial.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(sortedProjects) { project in
                        ProjectCard(project: project) {
                            onInfo(project)
                        }
                    }
                }
            }
        }
        .padding(.top, 40)
    }
}

private struct ProjectCard: View {
    @EnvironmentObject private var focus: FocusManager
    let project: Project
    let onTap: () -> Void

    private var weeklyProgress: ProjectGoalProgress {
        focus.weeklyGoalProgress(for: project)
    }

    private var ratioText: String {
        if let goal = weeklyProgress.goalHours, goal > 0 {
            return String(format: "%.1fh/%.1fh", weeklyProgress.actualHours, goal)
        }
        return String(format: "%.1fh focused", weeklyProgress.actualHours)
    }

    var body: some View {
        let gradient = ProjectGradientPalette.gradient(at: project.gradientIndex)
        VStack(spacing: 12) {
            Text(project.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                if weeklyProgress.goalHours != nil {
                    HStack {
                        Text(ratioText)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    ProgressView(value: min(max(weeklyProgress.progressFraction, 0), 1), total: 1)
                        .tint(Color.white)
                    Text(String(format: "%.1f%%", min(max(weeklyProgress.progressFraction, 0), 1) * 100))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%.1f h", weeklyProgress.actualHours))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("this week")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            LinearGradient(colors: [gradient.start, gradient.end], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 14)
        .onTapGesture {
            Haptics.heavy()
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

}

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @Query private var allProjects: [Project]
    @State private var title: String = ""
    @State private var hardBlockEnabled: Bool = false
    @State private var hardBlockSelection = FamilyActivitySelection()
    @State private var showingHardBlockPicker = false
    @State private var authorizationDenied = false
    @State private var hasWeeklyGoal: Bool = false
    @State private var weeklyGoalHoursInput: Double = 10

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sessionActive: Bool {
        focus.currentSession != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.09, blue: 0.20),
                        Color(red: 0.04, green: 0.06, blue: 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        if sessionActive {
                            BannerView(text: "End the current focus session to change hard blocking settings.")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Create a project")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Text("Track focus hours with a dedicated space and optional hard blocking.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ProjectFormCard(title: "Name",
                                        subtitle: "Give your project a clear purpose.",
                                        icon: "pencil") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("e.g. Thesis, Product launch, Reading list", text: $title)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled(false)
                                    .padding()
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .foregroundColor(.white)

                                Text("This will appear on your home screen and insights.")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }

                        ProjectFormCard(title: "Weekly goal",
                                        subtitle: "Optional target for this project (resets every Sunday).",
                                        icon: "flag.fill") {
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle(isOn: $hasWeeklyGoal) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Track a weekly goal")
                                            .font(.headline.weight(.medium))
                                            .foregroundStyle(.white)
                                        Text("Goals across projects are capped at 112h/week.")
                                            .font(.footnote)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                                .tint(Color.cyan)
                                .disabled(!canAddGoal)

                                if !canAddGoal {
                                    Text("You’ve reached the 112h/week cap. Lower another project’s goal to add one here.")
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.7))
                                } else if hasWeeklyGoal {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Slider(value: $weeklyGoalHoursInput, in: 1...sliderUpperBound, step: 1)
                                            .tint(.white)
                                            .onChange(of: weeklyGoalHoursInput) { _, newValue in
                                                weeklyGoalHoursInput = clampedGoalInput(newValue)
                                                Haptics.soft()
                                            }
                                        HStack {
                                            Text("Goal: \(Int(weeklyGoalHoursInput)) h / week")
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text("\(Int(remainingGoalBudget))h left in budget")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                    }
                                }
                            }
                        }

                        ProjectFormCard(title: "Hard blocking",
                                        subtitle: "Automatically shield specific apps whenever this project is active.",
                                        icon: "shield.lefthalf.fill") {
                            VStack(alignment: .leading, spacing: 16) {
                                Toggle(isOn: $hardBlockEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable project hard blocking")
                                            .font(.headline.weight(.medium))
                                            .foregroundStyle(.white)
                                        Text("Locks away distractions tailored to this project.")
                                            .font(.footnote)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                                .tint(Color.purple)
                                .disabled(sessionActive)
                                .onChange(of: hardBlockEnabled) { _, newValue in
                                    Task { @MainActor in
                                        guard !sessionActive else {
                                            hardBlockEnabled = false
                                            return
                                        }
                                        if newValue {
                                            let approved = await HardBlockManager.shared.ensureAuthorization()
                                            if approved {
                                                authorizationDenied = false
                                                if hardBlockSelection.isEmpty {
                                                    showingHardBlockPicker = true
                                                }
                                            } else {
                                                hardBlockEnabled = false
                                                authorizationDenied = true
                                            }
                                        } else {
                                            authorizationDenied = false
                                        }
                                    }
                                }

                                Button {
                                    Haptics.heavy()
                                    showingHardBlockPicker = true
                                } label: {
                                    Label("Choose apps and websites", systemImage: "square.and.pencil")
                                        .font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 11)
                                        .background(Color.white.opacity(hardBlockEnabled ? 0.2 : 0.08), in: Capsule())
                                        .foregroundStyle(Color.white.opacity(hardBlockEnabled ? 1 : 0.65))
                                }
                                .buttonStyle(.plain)
                                .disabled(!hardBlockEnabled || sessionActive)
                                .opacity((hardBlockEnabled && !sessionActive) ? 1 : 0.6)

                                Text(hardBlockSummary)
                                    .font(.footnote)
                                    .foregroundStyle(authorizationDenied ? .red : Color.white.opacity(0.7))
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Project")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.heavy()
                        dismiss()
                    }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.heavy()
                        save()
                    } label: {
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .tint(.white)
        .familyActivityPicker(isPresented: $showingHardBlockPicker, selection: $hardBlockSelection)
        .onChange(of: hardBlockSelection) { _, _ in
            authorizationDenied = false
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let goalHours: Double? = {
            guard hasWeeklyGoal, canAddGoal else { return nil }
            return clampedGoalInput(weeklyGoalHoursInput)
        }()
        let selectionData = HardBlockManager.shared.encodeSelection(hardBlockSelection)
        let project = Project(title: trimmed,
                              gradientIndex: nextGradientIndex(),
                              weeklyGoalHours: goalHours,
                              hardBlockEnabled: hardBlockEnabled,
                              hardBlockSelectionData: hardBlockEnabled ? selectionData : nil)
        modelContext.insert(project)
        if modelContext.saveOrRollback() {
            Analytics.track("project_created", [
                "project_id": project.id.uuidString
            ])
            dismiss()
        }
    }

    private func nextGradientIndex() -> Int {
        let existing = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        let next = (existing.map { $0.gradientIndex }.max() ?? -1) + 1
        return next
    }

    private var goalCapHours: Double { 112 }

    private var existingGoalHours: Double {
        allProjects
            .compactMap { $0.weeklyGoalHours }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    private var remainingGoalBudget: Double {
        max(0, goalCapHours - existingGoalHours)
    }

    private var canAddGoal: Bool { remainingGoalBudget >= 1 }

    private var sliderUpperBound: Double {
        guard remainingGoalBudget > 0 else { return 1 }
        return remainingGoalBudget
    }

    private func clampedGoalInput(_ value: Double) -> Double {
        guard remainingGoalBudget > 0 else { return 0 }
        return min(max(1, value), remainingGoalBudget)
    }

    private var hardBlockSummary: String {
        if authorizationDenied {
            return "Screen Time permission required. Open Settings → Screen Time to grant access."
        }
        if sessionActive {
            return "Pause your current focus session to adjust blocking."
        }
        if !hardBlockEnabled {
            return "Hard blocking is disabled."
        }
        if hardBlockSelection.isEmpty {
            return "No apps or websites selected yet."
        }
        var parts: [String] = []
        if hardBlockSelection.includeEntireCategory {
            parts.append("All categories")
        } else if !hardBlockSelection.categoryTokens.isEmpty {
            parts.append("\(hardBlockSelection.categoryTokens.count) categor\(hardBlockSelection.categoryTokens.count == 1 ? "y" : "ies")")
        }
        if !hardBlockSelection.applicationTokens.isEmpty {
            parts.append("\(hardBlockSelection.applicationTokens.count) app\(hardBlockSelection.applicationTokens.count == 1 ? "" : "s")")
        }
        if !hardBlockSelection.webDomainTokens.isEmpty {
            parts.append("\(hardBlockSelection.webDomainTokens.count) domain\(hardBlockSelection.webDomainTokens.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var focus: FocusManager
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @State private var hardBlockSelection = FamilyActivitySelection()
    @State private var showingHardBlockPicker = false
    @State private var authorizationDenied = false
    @State private var showDeleteConfirmation = false
    @State private var editedTitle: String = ""
    @State private var hasWeeklyGoal: Bool = false
    @State private var weeklyGoalHoursInput: Double = 10
    @State private var didLoadGoalState = false
    @Query private var allProjects: [Project]

    private var totalHours: Double { focus.totalDuration(for: project) / 3600 }
    private var sessionCount: Int { project.sessionsUnwrapped.count }
    private var sessionActive: Bool { focus.currentSession != nil }
    private var weeklyProgress: ProjectGoalProgress { focus.weeklyGoalProgress(for: project) }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.08, blue: 0.19),
                        Color(red: 0.03, green: 0.04, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        if sessionActive {
                            BannerView(text: "Stop the active session to change hard blocking settings.")
                        }

                        ProjectFormCard(title: "Name",
                                        subtitle: "Rename this project to keep things organized.",
                                        icon: "pencil") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Project name", text: $editedTitle)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled(false)
                                    .padding()
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .foregroundColor(.white)
                                    .onSubmit { commitRename() }

                                Text(nameHint)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(project.title)
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Text("Track how this project is progressing and adjust its blocking rules.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ProjectFormCard(title: "At a glance",
                                        subtitle: "Hours logged and sessions completed so far.",
                                        icon: "chart.bar.doc.horizontal") {
                            HStack(spacing: 12) {
                                StatPill(value: String(format: "%.2f", totalHours), label: "hours tracked", systemIcon: "clock.arrow.circlepath")
                                StatPill(value: "\(sessionCount)", label: "sessions", systemIcon: "list.number")
                            }
                        }

                        ProjectFormCard(title: "Weekly goal",
                                        subtitle: "Set a per-project target that resets every Sunday.",
                                        icon: "flag.fill") {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(hoursString(weeklyProgress.actualHours)) h")
                                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)
                                        Text("logged this week")
                                            .font(.footnote)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    Spacer()
                                    if hasWeeklyGoal, let goal = weeklyProgress.goalHours {
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text("\(hoursString(goal)) h")
                                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.white)
                                            Text("weekly goal")
                                                .font(.footnote)
                                                .foregroundStyle(.white.opacity(0.7))
                                        }
                                    }
                                }

                                if hasWeeklyGoal, weeklyProgress.goalHours != nil {
                                    ProgressView(value: weeklyProgress.progressFraction, total: 1)
                                        .tint(Color.cyan)
                                    Text(goalStatusText(for: weeklyProgress))
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.8))
                                } else {
                                    Text("Enable a weekly goal to compare this week's progress against a target.")
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.8))
                                }

                                Toggle(isOn: $hasWeeklyGoal) {
                                    Text("Track a weekly target")
                                        .font(.headline.weight(.medium))
                                        .foregroundStyle(.white)
                                }
                                .tint(Color.cyan)
                                .disabled(goalCapReachedForNewHours)

                                if goalCapReachedForNewHours && !hasWeeklyGoal {
                                    Text("Total weekly goals are capped at \(Int(goalCapHours))h. Lower another project's goal to add one here.")
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.7))
                                }

                                if hasWeeklyGoal {
                                    VStack(alignment: .leading, spacing: 10) {
                                        if sliderUpperBound < 1 {
                                            Text("Weekly goal cap reached. Lower another project's goal to add hours here.")
                                                .font(.footnote)
                                                .foregroundStyle(.white.opacity(0.7))
                                        } else {
                                            Slider(value: $weeklyGoalHoursInput, in: 1...sliderUpperBound, step: 1)
                                                .tint(.white)
                                                .onChange(of: weeklyGoalHoursInput) { _, newValue in
                                                    let clamped = clampedGoalInput(newValue)
                                                    if clamped != weeklyGoalHoursInput {
                                                        weeklyGoalHoursInput = clamped
                                                    }
                                                    Haptics.soft()
                                                }
                                            HStack {
                                                Text("Goal: \(Int(weeklyGoalHoursInput)) h / week")
                                                    .font(.footnote.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                Spacer()
                                                Text("\(Int(remainingBudgetAfterSelection))h capacity left")
                                                    .font(.caption)
                                                    .foregroundStyle(.white.opacity(0.6))
                                            }
                                            Text("Auto-saved")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                    }
                                }

                                Text("Goals reset every Sunday at midnight.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }

                        ProjectFormCard(title: "Hard blocking",
                                        subtitle: "Customize which apps to shield whenever this project is active.",
                                        icon: "shield.lefthalf.fill") {
                            VStack(alignment: .leading, spacing: 16) {
                                Toggle(isOn: $project.hardBlockEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable project hard blocking")
                                            .font(.headline.weight(.medium))
                                            .foregroundStyle(.white)
                                        Text("Keeps distracting apps and sites locked whenever this project is active.")
                                            .font(.footnote)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                                .tint(Color.purple)
                                .disabled(sessionActive)
                                .onChange(of: project.hardBlockEnabled) { _, newValue in
                                    Task { @MainActor in
                                        guard !sessionActive else {
                                            project.hardBlockEnabled = false
                                            return
                                        }
                                        if newValue {
                                            let approved = await HardBlockManager.shared.ensureAuthorization()
                                            if approved {
                                                authorizationDenied = false
                                                if hardBlockSelection.isEmpty {
                                                    showingHardBlockPicker = true
                                                } else if focus.currentSession?.project?.id == project.id {
                                                    _ = HardBlockManager.shared.activateHardBlock(for: project)
                                                }
                                            } else {
                                                project.hardBlockEnabled = false
                                                authorizationDenied = true
                                            }
                                        } else {
                                            authorizationDenied = false
                                            if focus.currentSession?.project?.id == project.id {
                                                HardBlockManager.shared.deactivateHardBlock()
                                            }
                                        }
                                        modelContext.saveOrRollback()
                                    }
                                }

                                Button {
                                    showingHardBlockPicker = true
                                } label: {
                                    Label("Choose apps and websites", systemImage: "square.and.pencil")
                                        .font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 11)
                                        .background(Color.white.opacity(project.hardBlockEnabled ? 0.2 : 0.08), in: Capsule())
                                        .foregroundStyle(Color.white.opacity(project.hardBlockEnabled ? 1 : 0.65))
                                }
                                .buttonStyle(.plain)
                                .disabled(!project.hardBlockEnabled || sessionActive)
                                .opacity((project.hardBlockEnabled && !sessionActive) ? 1 : 0.6)

                                Text(hardBlockSummary)
                                    .font(.footnote)
                                    .foregroundStyle(authorizationDenied ? .red : Color.white.opacity(0.7))
                            }
                        }

                        ProjectFormCard(title: "Danger zone",
                                        subtitle: "Remove this project and stop tracking future hours.",
                                        icon: "trash.fill") {
                            Button(role: .destructive) {
                                Haptics.warning()
                                showDeleteConfirmation = true
                            } label: {
                                Text("Delete \(project.title)")
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.heavy()
                        commitRename()
                        dismiss()
                    }
                        .foregroundStyle(.white)
                }
            }
        }
        .tint(.white)
        .onAppear {
            if let stored = HardBlockManager.shared.decodeSelection(from: project.hardBlockSelectionData) {
                hardBlockSelection = stored
            }
            editedTitle = project.title
            bootstrapWeeklyGoalStateIfNeeded()
        }
        .onChange(of: hardBlockSelection) { _, newValue in
            guard !sessionActive else { return }
            project.hardBlockSelectionData = HardBlockManager.shared.encodeSelection(newValue)
            guard modelContext.saveOrRollback() else { return }
            guard project.hardBlockEnabled else { return }
            if newValue.isEmpty {
                if focus.currentSession?.project?.id == project.id {
                    HardBlockManager.shared.deactivateHardBlock()
                }
            } else if focus.currentSession?.project?.id == project.id {
                _ = HardBlockManager.shared.activateHardBlock(for: project)
            }
        }
        .familyActivityPicker(isPresented: $showingHardBlockPicker, selection: $hardBlockSelection)
        .alert("Delete Project?", isPresented: $showDeleteConfirmation, actions: {
            Button("Delete", role: .destructive) {
                Haptics.warning()
                deleteProject()
            }
            Button("Cancel", role: .cancel) {
                Haptics.heavy()
            }
        }, message: {
            Text("Existing sessions will remain but will no longer be associated with this project.")
        })
        .onChange(of: hasWeeklyGoal) { _, newValue in
            applyGoalToggle(newValue)
        }
        .onChange(of: weeklyGoalHoursInput) { _, newValue in
            guard hasWeeklyGoal else { return }
            let clamped = clampedGoalInput(newValue)
            if clamped != weeklyGoalHoursInput {
                weeklyGoalHoursInput = clamped
            }
            project.weeklyGoalHours = clamped >= 1 ? clamped : nil
            modelContext.saveOrRollback()
        }
    }

    private var nameHint: String {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Names can’t be empty." : "Changes save when you tap Done."
    }

    private func commitRename() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editedTitle = project.title
            return
        }
        guard trimmed != project.title else { return }
        project.title = trimmed
        modelContext.saveOrRollback()
    }

    private var hardBlockSummary: String {
        if sessionActive {
            return "Stop the active session to edit blocking."
        }
        if !project.hardBlockEnabled {
            return "Hard blocking is disabled."
        }
        if hardBlockSelection.isEmpty {
            return "No apps or websites selected yet."
        }
        var parts: [String] = []
        if hardBlockSelection.includeEntireCategory {
            parts.append("All categories")
        } else if !hardBlockSelection.categoryTokens.isEmpty {
            parts.append("\(hardBlockSelection.categoryTokens.count) categor\(hardBlockSelection.categoryTokens.count == 1 ? "y" : "ies")")
        }
        if !hardBlockSelection.applicationTokens.isEmpty {
            parts.append("\(hardBlockSelection.applicationTokens.count) app\(hardBlockSelection.applicationTokens.count == 1 ? "" : "s")")
        }
        if !hardBlockSelection.webDomainTokens.isEmpty {
            parts.append("\(hardBlockSelection.webDomainTokens.count) domain\(hardBlockSelection.webDomainTokens.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func bootstrapWeeklyGoalStateIfNeeded() {
        guard !didLoadGoalState else { return }
        if let stored = project.weeklyGoalHours, stored > 0 {
            weeklyGoalHoursInput = stored
            hasWeeklyGoal = true
        } else {
            weeklyGoalHoursInput = clampedGoalInput(weeklyGoalHoursInput)
            hasWeeklyGoal = false
        }
        didLoadGoalState = true
    }

    private func applyGoalToggle(_ isEnabled: Bool) {
        if isEnabled {
            let clamped = clampedGoalInput(weeklyGoalHoursInput > 0 ? weeklyGoalHoursInput : 1)
            guard clamped >= 1 else {
                hasWeeklyGoal = false
                return
            }
            weeklyGoalHoursInput = clamped
            project.weeklyGoalHours = clamped
        } else {
            project.weeklyGoalHours = nil
        }
        modelContext.saveOrRollback()
    }

    private var goalCapHours: Double { 112 }

    private var otherGoalHours: Double {
        allProjects
            .filter { $0.id != project.id }
            .compactMap { $0.weeklyGoalHours }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    private var availableGoalBudget: Double {
        max(0, goalCapHours - otherGoalHours)
    }

    private var sliderUpperBound: Double {
        let current = max(0, project.weeklyGoalHours ?? 0)
        let allowed = min(goalCapHours, availableGoalBudget)
        return max(current, allowed)
    }

    private func clampedGoalInput(_ value: Double) -> Double {
        let upper = sliderUpperBound
        guard upper >= 1 else { return 0 }
        return min(max(1, value), upper)
    }

    private var remainingBudgetAfterSelection: Double {
        let selected = hasWeeklyGoal ? max(0, weeklyGoalHoursInput) : 0
        return max(0, goalCapHours - otherGoalHours - selected)
    }

    private var goalCapReachedForNewHours: Bool {
        sliderUpperBound < 1 && (project.weeklyGoalHours ?? 0) <= 0
    }

    private func goalStatusText(for progress: ProjectGoalProgress) -> String {
        guard let goal = progress.goalHours else {
            return "No goal yet — enable one to compare progress."
        }
        let remaining = goal - progress.actualHours
        if remaining <= 0 {
            return "Goal met for this week. Fantastic work!"
        }
        return "\(hoursString(max(remaining, 0))) h to go before Sunday."
    }

    private func hoursString(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private func deleteProject() {
        if let session = focus.currentSession, session.project?.id == project.id {
            session.project = nil
            HardBlockManager.shared.deactivateHardBlock()
        }
        modelContext.delete(project)
        if modelContext.saveOrRollback() {
            dismiss()
        }
    }
}

private struct ProjectFormCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }
}

struct ProjectSelectionTile: View {
    let title: String
    let ratioText: String
    let detailText: String
    let gradient: (start: Color, end: Color)
    let progressFraction: Double?
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.heavy()
            action()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 0)

                Text(ratioText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                if let fraction = progressFraction {
                    GeometryReader { proxy in
                        let width = proxy.size.width * max(0, min(1, fraction))
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.25))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: width)
                        }
                        .frame(height: 10)
                    }
                    .frame(height: 10)

                    Text(String(format: "%.0f%% of goal", max(0, min(1, fraction)) * 100))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                LinearGradient(colors: [gradient.start, gradient.end], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 10)
        }
        .buttonStyle(.projectSelection)
    }
}

struct ProjectSelectionNoProjectTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.heavy()
            action()
        }) {
            VStack(spacing: 8) {
                Text("No project")
                    .font(.system(size: 18, weight: .bold))
                Text("Stay unassigned for this session.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                LinearGradient(colors: [Color(red: 0.21, green: 0.25, blue: 0.45), Color(red: 0.10, green: 0.12, blue: 0.26)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 10)
        }
        .buttonStyle(.projectSelection)
    }
}

struct ProjectSelectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

private extension ButtonStyle where Self == ProjectSelectionButtonStyle {
    static var projectSelection: ProjectSelectionButtonStyle { ProjectSelectionButtonStyle() }
}
struct EmptyProjectsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Create a project from the Home tab to start assigning focus sessions.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct BannerView: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 18, weight: .semibold))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct StatPill: View {
    let value: String
    let label: String
    let systemIcon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(label.capitalized)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Shared transitions

private struct FocusAnimModifier: ViewModifier {
    enum Phase { case insert, remove, identity }
    let phase: Phase

    func body(content: Content) -> some View {
        switch phase {
        case .insert:
            content.opacity(0).scaleEffect(0.96).offset(y: 14)
        case .remove:
            content.opacity(0).scaleEffect(0.96).offset(y: -14)
        case .identity:
            content
        }
    }
}

private extension AnyTransition {
    static var focusElegant: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FocusAnimModifier(phase: .insert),
                                 identity: FocusAnimModifier(phase: .identity)),
            removal: .modifier(active: FocusAnimModifier(phase: .remove),
                               identity: FocusAnimModifier(phase: .identity))
        )
    }
}

private struct CompletedSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @Bindable var session: FocusSession
    var onStop: () -> Void
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]
    @Query private var prefsList: [Preferences]

    @State private var selectedProjectID: UUID?

    private var prefs: Preferences? { prefsList.first }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.16),
                        Color(red: 0.02, green: 0.03, blue: 0.09)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        VStack(alignment: .center, spacing: 8) {
                            Text("Session complete!")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Text(congratulationText())
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 12)

                        ProjectFormCard(title: "Assign to project",
                                        subtitle: "Log these focus hours against a project (optional).",
                                        icon: "target") {
                            Picker("Project", selection: $selectedProjectID) {
                                Text("None").tag(UUID?.none)
                                ForEach(projects) { project in
                                    Text(project.title).tag(Optional(project.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(.white)
                        }

                        CalendarPreviewCard(session: session,
                                            projectTitle: selectedProjectTitle,
                                            calendarIdentifier: prefs?.calendarCalendarIdentifier,
                                            calendarEnabled: prefs?.calendarIntegrationEnabled == true,
                                            locationStatus: "Location will be added if allowed")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                }
                .overlay(
                    ConfettiView(duration: 2.0)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        Haptics.heavy()
                        dismiss()
                    }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Haptics.success()
                        saveAndFinish()
                    }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.white)
        .onAppear {
            selectedProjectID = session.project?.id
        }
    }

    private func saveAndFinish() {
        if let selectedProjectID,
           let matched = projects.first(where: { $0.id == selectedProjectID }) {
            session.project = matched
        } else {
            session.project = nil
        }
        if modelContext.saveOrRollback() {
            SnapshotWriter.refresh(modelContext: modelContext, currentSession: session, stateOverride: .stopped)
            onStop()
            dismiss()
        }
    }

    private var selectedProjectTitle: String? {
        if let id = selectedProjectID,
           let project = projects.first(where: { $0.id == id }) {
            return project.title
        }
        return session.project?.title
    }

    private func congratulationText(now: Date = .now) -> String {
        let start = session.startedAt
        let end = session.endedAt ?? now
        let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 1 {
            let hoursPart = hours == 1 ? "1 hour" : "\(hours) hours"
            let minutesPart = minutes > 0 ? " and \(minutes) \(minutes == 1 ? "minute" : "minutes")" : ""
            return "Well done! You focused for \(hoursPart)\(minutesPart)."
        } else {
            return "Well done! You focused for \(minutes) \(minutes == 1 ? "minute" : "minutes")."
        }
    }
}

enum ProjectGradientPalette {
    private static let baseGradients: [(start: Color, end: Color)] = [
        (Color(red: 0.27, green: 0.56, blue: 0.99), Color(red: 0.60, green: 0.28, blue: 0.98)),
        (Color(red: 0.33, green: 0.76, blue: 0.86), Color(red: 0.20, green: 0.48, blue: 0.97)),
        (Color(red: 0.99, green: 0.62, blue: 0.45), Color(red: 0.95, green: 0.30, blue: 0.55)),
        (Color(red: 0.98, green: 0.80, blue: 0.36), Color(red: 0.96, green: 0.48, blue: 0.31)),
        (Color(red: 0.54, green: 0.43, blue: 0.99), Color(red: 0.28, green: 0.21, blue: 0.58)),
        (Color(red: 0.34, green: 0.64, blue: 0.99), Color(red: 0.22, green: 0.30, blue: 0.64)),
        (Color(red: 0.99, green: 0.45, blue: 0.69), Color(red: 0.58, green: 0.32, blue: 0.93)),
        (Color(red: 0.46, green: 0.35, blue: 0.82), Color(red: 0.19, green: 0.18, blue: 0.38))
    ]

    static func gradient(at index: Int) -> (start: Color, end: Color) {
        precondition(!baseGradients.isEmpty, "Project gradient palette must contain at least one entry")
        if index < baseGradients.count { return baseGradients[index] }
        let base = baseGradients[index % baseGradients.count]
        let cycle = max(1, index / baseGradients.count)
        let lighten = min(0.10, 0.04 * Double(cycle))
        let darken = min(0.15, 0.05 * Double(cycle))
        let start = adjust(base.start, brightnessDelta: lighten)
        let end = adjust(base.end, brightnessDelta: -darken)
        return (start, end)
    }

    private static func adjust(_ color: Color, brightnessDelta: Double) -> Color {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }
        brightness = max(0, min(1, brightness + CGFloat(brightnessDelta)))
        return Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
    }
}

private extension FamilyActivitySelection {
    var isEmpty: Bool {
        !includeEntireCategory &&
        applicationTokens.isEmpty &&
        categoryTokens.isEmpty &&
        webDomainTokens.isEmpty
    }
}
