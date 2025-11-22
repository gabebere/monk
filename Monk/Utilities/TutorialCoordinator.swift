import SwiftUI

enum TutorialStage: CaseIterable, Identifiable {
    case weeklyGoal
    case createProject
    case addWidgets
    case startSession

    var id: Self { self }

    var title: String {
        switch self {
        case .weeklyGoal:
            return "Set your weekly goal"
        case .createProject:
            return "Create your first project"
        case .addWidgets:
            return "Add progress widgets"
        case .startSession:
            return "Start a focus session"
        }
    }

    var message: String {
        switch self {
        case .weeklyGoal:
            return "Open the Settings tab and adjust the Weekly Goal card to set your target hours."
        case .createProject:
            return "Jump to Home and use the plus button to add a project for what you’re working on."
        case .addWidgets:
            return "Head back to Settings, then open the widget guide to pin Monk where you need it."
        case .startSession:
            return "Return to Home and tap the focus button when you’re ready to start your first session."
        }
    }

    var preferredTab: AppTab {
        switch self {
        case .weeklyGoal, .addWidgets:
            return .settings
        case .createProject, .startSession:
            return .home
        }
    }

    var isLast: Bool { self == TutorialStage.allCases.last }

    func next() -> TutorialStage? {
        guard let idx = TutorialStage.allCases.firstIndex(of: self),
              idx + 1 < TutorialStage.allCases.count else { return nil }
        return TutorialStage.allCases[idx + 1]
    }
}

struct TutorialHighlightInfo: Equatable {
    let stage: TutorialStage
    let frame: CGRect
    let cornerRadius: CGFloat
}

@MainActor
final class TutorialCoordinator: ObservableObject {
    @Published var activeStage: TutorialStage?

    var tabSelectionHandler: ((AppTab) -> Void)?

    func start(at stage: TutorialStage = .weeklyGoal) {
        activeStage = stage
        tabSelectionHandler?(stage.preferredTab)
    }

    func advance() {
        guard let stage = activeStage else { return }
        if let next = stage.next() {
            activeStage = next
            tabSelectionHandler?(next.preferredTab)
        } else {
            activeStage = nil
        }
    }

    func skip() {
        activeStage = nil
    }
}
