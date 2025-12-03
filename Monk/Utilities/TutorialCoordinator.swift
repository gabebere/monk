import SwiftUI

enum TutorialStage: String, CaseIterable, Identifiable {
    case welcome
    case createProject
    case startSession
    case stopSession
    case calendar
    case location
    case insights
    case paywall

    static var ordered: [TutorialStage] {
        [.welcome, .createProject, .startSession, .stopSession, .calendar, .location, .insights, .paywall]
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Monk"
        case .createProject:
            return "Create your first project"
        case .startSession:
            return "Start your first focus session"
        case .stopSession:
            return "Finish your session"
        case .calendar:
            return "Sync your calendar"
        case .location:
            return "Add location context"
        case .insights:
            return "See your insights"
        case .paywall:
            return "Unlock Monk Pro"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "We’ll build Monk together on the real screens."
        case .createProject:
            return "Tap + on Home to add a real project."
        case .startSession:
            return "Use the Time to focus button to start."
        case .stopSession:
            return "Tap stop when you’re ready to wrap; we’ll show the summary."
        case .calendar:
            return "Pick the calendar Monk should save sessions to."
        case .location:
            return "Allow location to add where you worked."
        case .insights:
            return "Open Insights to review your plan and progress."
        case .paywall:
            return "Finish onboarding with Monk Pro."
        }
    }

    var preferredTab: AppTab {
        switch self {
        case .welcome, .createProject, .startSession, .stopSession:
            return .home
        case .calendar, .location:
            return .settings
        case .insights, .paywall:
            return .insights
        }
    }

    var isLast: Bool { self == TutorialStage.allCases.last }

    func next() -> TutorialStage? {
        guard let idx = TutorialStage.ordered.firstIndex(of: self),
              idx + 1 < TutorialStage.ordered.count else { return nil }
        return TutorialStage.ordered[idx + 1]
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

    func start(at stage: TutorialStage = .createProject) {
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

    func complete() {
        activeStage = nil
    }
}
