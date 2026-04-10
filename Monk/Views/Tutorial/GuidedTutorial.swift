import SwiftUI
import UIKit

enum GuidedTutorialStep: Int, CaseIterable {
    case createProject
    case openTasks
    case createTask
    case startFocusChoice
    case startFocusButtonOnly
    case stopFocus
    case finishSession
    case ready

    var title: String {
        switch self {
        case .createProject:
            return "Create Your First Project"
        case .openTasks:
            return "Open To-do's"
        case .createTask:
            return "Start With a To-do"
        case .startFocusChoice:
            return "Start Your First Focus"
        case .startFocusButtonOnly:
            return "Start With This To-do"
        case .stopFocus:
            return "Stop Focus"
        case .finishSession:
            return "Finish Session"
        case .ready:
            return "You're Ready"
        }
    }

    var message: String {
        switch self {
        case .createProject:
            return "Use + or Add Project to create your first project."
        case .openTasks:
            return "Great. Now tap To-do's."
        case .createTask:
            return "Tap an upcoming to-do to start focus with a reminder. If nothing is scheduled yet, you can also start from a project."
        case .startFocusChoice:
            return "Tap a project or to-do to begin. Monk will remember the project you choose for a to-do."
        case .startFocusButtonOnly:
            return "Tap this to-do to start a focus session. Monk will remember the project you choose for it."
        case .stopFocus:
            return "Now stop this focus session."
        case .finishSession:
            return "Tap Done in the completion sheet to finish."
        case .ready:
            return "Great, now you're set to start using Monk."
        }
    }

    var progressText: String {
        "Step \(rawValue + 1) of \(Self.allCases.count)"
    }

    var primaryButtonTitle: String? {
        switch self {
        case .ready:
            return "Start using Monk"
        default:
            return nil
        }
    }

    var prefersBottomInstructionCard: Bool {
        switch self {
        case .startFocusChoice, .startFocusButtonOnly:
            return true
        default:
            return false
        }
    }
}

enum GuidedTutorialAnchor: Hashable {
    case projectsAddButton
    case projectsContentArea
    case projectsEmptyCreateButton
    case homeTasksSectionButton
    case homeNewTaskButton
    case homeEmptyNewTaskButton
    case homeTaskRow(UUID)
    case homeStopButton
}

enum GuidedTutorialModalKind: Hashable {
    case newProject
    case taskEditor
    case projectPicker
    case completedSession
}

enum GuidedTutorialHomeSection: Equatable {
    case projects
    case tasks
}

enum GuidedTutorialEvent {
    case homeSectionChanged(GuidedTutorialHomeSection)
    case modalChanged(kind: GuidedTutorialModalKind, isPresented: Bool)
    case focusStarted(projectID: UUID?, taskID: UUID?)
    case focusStopped(willShowCompletionSheet: Bool)
    case completionDone
}

private struct ActiveGuidedTutorialStepKey: EnvironmentKey {
    static let defaultValue: GuidedTutorialStep? = nil
}

private struct GuidedTutorialCreatedProjectIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct GuidedTutorialCreatedTaskIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct GuidedTutorialBaselineProjectIDsKey: EnvironmentKey {
    static let defaultValue: Set<UUID> = []
}

private struct GuidedTutorialBaselineTaskIDsKey: EnvironmentKey {
    static let defaultValue: Set<UUID> = []
}

private struct GuidedTutorialEventHandlerKey: EnvironmentKey {
    static let defaultValue: (GuidedTutorialEvent) -> Void = { _ in }
}

extension EnvironmentValues {
    var activeGuidedTutorialStep: GuidedTutorialStep? {
        get { self[ActiveGuidedTutorialStepKey.self] }
        set { self[ActiveGuidedTutorialStepKey.self] = newValue }
    }

    var guidedTutorialCreatedProjectID: UUID? {
        get { self[GuidedTutorialCreatedProjectIDKey.self] }
        set { self[GuidedTutorialCreatedProjectIDKey.self] = newValue }
    }

    var guidedTutorialCreatedTaskID: UUID? {
        get { self[GuidedTutorialCreatedTaskIDKey.self] }
        set { self[GuidedTutorialCreatedTaskIDKey.self] = newValue }
    }

    var guidedTutorialBaselineProjectIDs: Set<UUID> {
        get { self[GuidedTutorialBaselineProjectIDsKey.self] }
        set { self[GuidedTutorialBaselineProjectIDsKey.self] = newValue }
    }

    var guidedTutorialBaselineTaskIDs: Set<UUID> {
        get { self[GuidedTutorialBaselineTaskIDsKey.self] }
        set { self[GuidedTutorialBaselineTaskIDsKey.self] = newValue }
    }

    var guidedTutorialEventHandler: (GuidedTutorialEvent) -> Void {
        get { self[GuidedTutorialEventHandlerKey.self] }
        set { self[GuidedTutorialEventHandlerKey.self] = newValue }
    }
}

struct GuidedTutorialAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [GuidedTutorialAnchor: Anchor<CGRect>] = [:]

    static func reduce(value: inout [GuidedTutorialAnchor: Anchor<CGRect>], nextValue: () -> [GuidedTutorialAnchor: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func guidedTutorialAnchor(_ anchor: GuidedTutorialAnchor) -> some View {
        anchorPreference(key: GuidedTutorialAnchorPreferenceKey.self, value: .bounds) { [anchor: $0] }
    }
}

struct GuidedTutorialSpotlightOverlay: View {
    let step: GuidedTutorialStep
    let holes: [CGRect]
    let topInset: CGFloat
    let bottomInset: CGFloat
    let blocksTouchesOutsideHoles: Bool
    let onPrimaryAction: (() -> Void)?
    let onSkip: () -> Void

    private var spotlightHoles: [CGRect] {
        holes.map { $0.insetBy(dx: -TutorialSpotlightStyle.holeInset, dy: -TutorialSpotlightStyle.holeInset) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if blocksTouchesOutsideHoles {
                TutorialTouchShield(holes: spotlightHoles)
                    .ignoresSafeArea()
            }

            ForEach(Array(spotlightHoles.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: TutorialSpotlightStyle.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: TutorialSpotlightStyle.strokeLineWidth)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(step.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(step.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(step.progressText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    if let title = step.primaryButtonTitle, let onPrimaryAction {
                        Button(title) {
                            onPrimaryAction()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(.white)
                        .foregroundStyle(.black)
                    }
                    Button("Skip") {
                        onSkip()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.white.opacity(0.24))
                    .foregroundStyle(.white)
                }
            }
            .padding(14)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .frame(maxWidth: .infinity,
                   maxHeight: .infinity,
                   alignment: step.prefersBottomInstructionCard ? .bottom : .top)
            .padding(.horizontal, 16)
            .padding(.top, step.prefersBottomInstructionCard ? 0 : topInset + 16)
            .padding(.bottom, step.prefersBottomInstructionCard ? bottomInset + TutorialSpotlightStyle.bottomCardClearance : 0)
        }
    }
}

private struct TutorialTouchShield: UIViewRepresentable {
    let holes: [CGRect]

    func makeUIView(context: Context) -> TutorialTouchShieldView {
        let view = TutorialTouchShieldView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TutorialTouchShieldView, context: Context) {
        uiView.holes = holes
    }
}

private final class TutorialTouchShieldView: UIView {
    var holes: [CGRect] = []

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for hole in holes where hole.contains(point) {
            return false
        }
        return true
    }
}

private enum TutorialSpotlightStyle {
    static let holeInset: CGFloat = 4
    static let cornerRadius: CGFloat = 18
    static let strokeLineWidth: CGFloat = 2
    static let bottomCardClearance: CGFloat = 96
}
