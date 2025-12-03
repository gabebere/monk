import SwiftUI

struct OnboardingCardView: View {
    struct Status {
        let text: String
        let color: Color
    }

    let card: OnboardingCard
    let status: Status?
    let onContinue: () -> Void
    let onSkip: (() -> Void)?
    var isLoading: Bool = false

    var body: some View {
        ZStack {
            AnimatingBackground()
            VStack(spacing: 26) {
                Spacer()
                VStack(spacing: 12) {
                    Text(card.title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(card.message)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                    if let status {
                        Text(status.text)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(status.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(status.color.opacity(0.14), in: Capsule())
                    }
                }
                Spacer()
                VStack(spacing: 12) {
                    Button(action: {
                        Haptics.heavy()
                        guard !isLoading else { return }
                        onContinue()
                    }) {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }
                            Text(isLoading ? "Working..." : card.cta)
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [
                                Color(red: 0.32, green: 0.52, blue: 0.94),
                                Color(red: 0.22, green: 0.34, blue: 0.66)
                            ], startPoint: .leading, endPoint: .trailing)
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(isLoading)
                    if let onSkip {
                        Button(action: {
                            Haptics.heavy()
                            onSkip()
                        }) {
                            Text("Skip for now")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .preferredColorScheme(.dark)
    }
}

extension OnboardingCard {
    var title: String {
        switch self {
        case .welcome: return "Welcome to Monk"
        case .screenTime: return "Stay on task"
        case .projectIntro: return "Organize your projects"
        case .createProject: return "Creating your first one"
        case .sessionExplain: return "Focus is a skill"
        case .startSession: return "Start your first session"
        case .calendar: return "See your work on the calendar"
        case .location: return "Remember where you worked"
        case .stopSession: return "End the session"
        case .insightsExplain: return "Understand your time"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "You get about 112 waking hours each week. Monk helps you decide where they go, block distractions, and keep track of what you actually did."
        case .screenTime:
            return "Monk uses Apple’s Screen Time to block apps you’ve marked as distracting during a focus session."
        case .projectIntro:
            return "Monk is built around projects: classes, hobbies, habits, or work. Each project has its own goals and allowed/blocked apps."
        case .createProject:
            return "Create a project for a class, hobby, or habit. Set a goal and choose which apps should be blocked while you’re working on it."
        case .sessionExplain:
            return "Focus gets better with practice. During a session, Monk blocks your hard-blocked apps so you can stay with one task instead of juggling five."
        case .startSession:
            return "Start a focus session for your first project. Tap 'Time to focus?', and see what it’s like to work without the usual distractions."
        case .calendar:
            return "Your focus sessions are saved to your calendar, so you can see when you actually worked and how your week is filling up."
        case .location:
            return "Optionally add on-device location tags to your sessions, so you can see where you tend to focus best. This stays on your phone."
        case .stopSession:
            return "When you’re done, end the session. We’ll save the time, update your stats, and keep your calendar in sync."
        case .insightsExplain:
            return "Insights shows a clean summary of your focus time so you can easily see what you’ve already done."
        }
    }

    var cta: String {
        switch self {
        case .welcome: return "Begin"
        case .screenTime: return "Grant Screen Time"
        case .projectIntro: return "Continue"
        case .createProject: return "Create a project"
        case .sessionExplain: return "Continue"
        case .startSession: return "Start session"
        case .calendar: return "Grant Calendar access"
        case .location: return "Grant Location access"
        case .stopSession: return "Stop the session"
        case .insightsExplain: return "Continue"
        }
    }
}
