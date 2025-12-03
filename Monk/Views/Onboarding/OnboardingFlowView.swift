import SwiftUI
import SwiftData

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case createProject
    case hardBlock
    case focusSession
    case calendar
    case location
    case insights
    case paywall

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome to Monk"
        case .createProject: return "Set up your first project"
        case .hardBlock: return "Stay distraction-free"
        case .focusSession: return "Try a focus session"
        case .calendar: return "Save sessions to Calendar"
        case .location: return "Add context with location"
        case .insights: return "See your insights"
        case .paywall: return "Unlock Monk Pro"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "We’ll build your workspace together in a few quick steps."
        case .createProject:
            return "Tap + to add your first project, just like on your Home screen."
        case .hardBlock:
            return "Allow Screen Time so Monk can hard block distractions while you focus."
        case .focusSession:
            return "Start and end a sample focus session to feel the flow."
        case .calendar:
            return "Let Monk save sessions to your calendar so your time is always visible."
        case .location:
            return "Optionally add where you worked to enrich your history."
        case .insights:
            return "Review your plan, progress, and goals in Insights."
        case .paywall:
            return "Finish onboarding with Monk Pro and unlock the full experience."
        }
    }

    var primaryLabel: String {
        switch self {
        case .welcome: return "Let’s start"
        case .createProject: return "Open projects"
        case .hardBlock: return "Enable Screen Time"
        case .focusSession: return "Start session"
        case .calendar: return "Allow Calendar"
        case .location: return "Allow Location"
        case .insights: return "Show Insights"
        case .paywall: return "Continue to paywall"
        }
    }

    var secondaryLabel: String {
        switch self {
        case .focusSession: return "Skip demo"
        case .location: return "Skip location"
        case .insights: return "Skip"
        default: return "Skip"
        }
    }

    var showsSecondary: Bool {
        switch self {
        case .welcome, .paywall, .createProject, .hardBlock, .calendar: return false
        default: return true
        }
    }

    func next() -> OnboardingStep? {
        guard let idx = OnboardingStep.allCases.firstIndex(of: self),
              idx + 1 < OnboardingStep.allCases.count else { return nil }
        return OnboardingStep.allCases[idx + 1]
    }
}

private enum PermissionStatus {
    case idle, granted, denied

    var label: String {
        switch self {
        case .idle: return ""
        case .granted: return "Granted"
        case .denied: return "Unavailable"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .clear
        case .granted: return .green
        case .denied: return .red
        }
    }
}

struct OnboardingFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @State private var step: OnboardingStep = .welcome
    @State private var showingProjectSheet = false
    @State private var focusDemoRunning = false
    @State private var screenTimeStatus: PermissionStatus = .idle
    @State private var calendarStatus: PermissionStatus = .idle
    @State private var locationStatus: PermissionStatus = .idle
    @State private var showingInfo = false
    @State private var showSessionComplete = false
    @State private var showInsights = false

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            AnimatingBackground()
            VStack(alignment: .leading, spacing: 20) {
                header
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 14) {
                    Text(step.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(step.message)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.86))
                    statusBadges
                    if step == .createProject {
                        projectRack
                    }
                    if step == .focusSession {
                        focusInstructions
                    }
                }
                .padding(16)
                .background(cardBackground)
                .shadow(color: .black.opacity(isPermissionStep ? 0.28 : 0.18),
                        radius: isPermissionStep ? 20 : 14,
                        x: 0,
                        y: 10)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Spacer()
                actionButtons
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingProjectSheet) {
            NavigationStack {
                OnboardingProjectSheet(onSaved: {
                    showingProjectSheet = false
                    advance()
                }, onCancel: {
                    showingProjectSheet = false
                })
            }
        }
        .sheet(isPresented: $showInsights) {
            NavigationStack {
                InsightsView()
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Done") {
                                finish()
                            }
                            .font(.headline.weight(.semibold))
                        }
                    }
            }
        }
        .alert("Session completed", isPresented: $showSessionComplete) {
            Button("OK", action: advance)
        } message: {
            Text("Nice! You started and ended a focus session.")
        }
    }
}

private extension OnboardingFlowView {
    var header: some View {
        HStack {
            Text("Monk")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Text("\(stepIndex + 1)/\(OnboardingStep.allCases.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    var statusBadges: some View {
        HStack(spacing: 10) {
            if step == .hardBlock {
                badge(text: screenTimeStatus.label, color: screenTimeStatus.color)
            }
            if step == .calendar {
                badge(text: calendarStatus.label, color: calendarStatus.color)
            }
            if step == .location {
                badge(text: locationStatus.label, color: locationStatus.color)
            }
        }
    }

    var projectRack: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Projects")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showingProjectSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            RoundedRectangle(cornerRadius: 14)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6,4]))
                .foregroundStyle(.white.opacity(0.4))
                .frame(height: 80)
                .overlay(
                    Text("Tap + to add your first project")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                )
        }
    }

    var focusInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(focus.currentSession == nil ? "Press start, then end when ready." : "Now tap to end the session.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    func badge(text: String, color: Color) -> some View {
        Group {
            if !text.isEmpty {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }
        }
    }

    var cardBackground: some View {
        let base = isPermissionStep
        ? Color.white.opacity(0.10)
        : Color.white.opacity(0.06)
        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(base)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .foregroundStyle(.white)
            }
            .disabled(step == .focusSession && focusDemoRunning)
            if step.showsSecondary {
                Button {
                    advance()
                } label: {
                    Text(step.secondaryLabel)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            if step == .focusSession {
                focusDemoView
            }
        }
    }

    var focusDemoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(focusDemoRunning ? "Session running…" : "Tap to start, then we’ll end it together.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    var stepIndex: Int {
        OnboardingStep.allCases.firstIndex(of: step) ?? 0
    }

    var primaryLabel: String {
        if step == .focusSession, focus.currentSession != nil {
            return "End session"
        }
        return step.primaryLabel
    }

    func primaryAction() {
        switch step {
        case .welcome:
            advance()
        case .createProject:
            showingProjectSheet = true
        case .hardBlock:
            Task { @MainActor in
                let granted = await HardBlockManager.shared.ensureAuthorization()
                screenTimeStatus = granted ? .granted : .denied
                advance()
            }
        case .focusSession:
            runFocusDemo()
        case .calendar:
            Task {
                let granted = await CalendarIntegration.shared.requestAccess()
                await MainActor.run {
                    calendarStatus = granted ? .granted : .denied
                    advance()
                }
            }
        case .location:
            Task { @MainActor in
                let result = await LocationProvider.shared.requestLocation()
                locationStatus = (result != nil) ? .granted : .denied
                advance()
            }
        case .insights:
            showInsights = true
        case .paywall:
            PaywallManager.shared.presentPaywall()
            finish()
        }
    }

    func runFocusDemo() {
        if focus.currentSession == nil {
            focusDemoRunning = true
            let project = (try? modelContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])))?.first
            focus.start(project: project)
        } else {
            focus.stop()
            focusDemoRunning = false
            showSessionComplete = true
        }
    }

    func advance() {
        if let next = step.next() {
            step = next
        } else {
            finish()
        }
    }

    func finish() {
        onFinished()
        dismiss()
    }

    var isPermissionStep: Bool {
        step == .hardBlock || step == .calendar || step == .location
    }
}

// MARK: - Project creation sheet (lightweight for onboarding)
private struct OnboardingProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title: String = ""

    let onSaved: () -> Void
    let onCancel: () -> Void

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Create your first project")
                .font(.title.bold())
                .foregroundStyle(.white)
            Text("Name what you’re working on. You can adjust details later.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            TextField("e.g. Thesis, Dynamics, Product launch", text: $title)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundColor(.white)

            HStack {
                Button("Skip") {
                    onCancel()
                    dismiss()
                }
                .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Button("Save") {
                    save()
                }
                .disabled(isSaveDisabled)
                .foregroundStyle(isSaveDisabled ? .white.opacity(0.5) : .white)
            }
        }
        .padding(24)
        .background(
            LinearGradient(colors: [
                Color(red: 0.12, green: 0.07, blue: 0.26),
                Color(red: 0.08, green: 0.36, blue: 0.58)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        )
        .tint(.white)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let project = Project(title: trimmed,
                              gradientIndex: nextGradientIndex())
        modelContext.insert(project)
        if modelContext.saveOrRollback() {
            onSaved()
            dismiss()
        }
    }

    private func nextGradientIndex() -> Int {
        let existing = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        let next = (existing.map { $0.gradientIndex }.max() ?? -1) + 1
        return next
    }
}
