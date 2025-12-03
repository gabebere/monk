import Foundation

enum OnboardingCard: String, Identifiable {
    case welcome
    case screenTime
    case projectIntro
    case createProject
    case sessionExplain
    case startSession
    case calendar
    case location
    case stopSession
    case insightsExplain

    var id: Self { self }
}
