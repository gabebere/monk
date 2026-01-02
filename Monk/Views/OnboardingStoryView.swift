import SwiftUI
import UIKit

/// Story-style onboarding (tap left/right) with four narrative screens and a pricing handoff.
struct OnboardingStoryView: View {
    enum Step: Int, CaseIterable {
        case timeIdentity
        case attentionConstraint
        case focusSkill
        case paywall

        var isLast: Bool { self == .paywall }
    }

    struct Completion {
        let requestPricing: Bool
    }

    let onFinish: (Completion) -> Void

    @State private var step: Step = .timeIdentity

    var body: some View {
        ZStack {
            AnimatingBackground()

            GeometryReader { proxy in
                if let slide = slide(for: step) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .center, spacing: 14) {
                            Text(slide.headline)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.95))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, slide.titleTopPadding)
                        .frame(maxWidth: .infinity, alignment: .center)

                        HStack(alignment: .center, spacing: 0) {
                            VStack(alignment: .center, spacing: 12) {
                                Text(slide.body)
                                    .font(.system(size: 20, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineSpacing(6)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                } else {
                    Color.clear
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .onAppear { finish() }
                }
            }

            gestureOverlay
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                pageIndicator(for: step)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, proxy.size.height * 0.9)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Layout helpers

private extension OnboardingStoryView {
    var tapNavigationEnabled: Bool { true }
    var totalSteps: Int { Step.allCases.count }

    struct Slide {
        let headline: String
        let body: String
        let titleTopPadding: CGFloat
    }

    func slide(for step: Step) -> Slide? {
        switch step {
        case .timeIdentity:
            return Slide(
                headline: "A life is built in hours.",
                body: """
Everyone has the same amount of time in a week, but how you spend it shapes your work, your relationships, and who you become.

To become the person you want, there are two things you can change: your attention and your focus.
""",
                titleTopPadding: 130
            )
        case .attentionConstraint:
            return Slide(
                headline: "Attention determines where time goes.",
                body: """
What we pay attention to is what our time is spent on, often without us noticing.

Many things compete for our attention, and when they take it, time is pulled away from the work, relationships, and pursuits that matter most.
""",
                titleTopPadding: 120
            )
        case .focusSkill:
            return Slide(
                headline: "Focus is what keeps attention from drifting.",
                body: """
Once your attention is on something, focus is what allows you to stay with it. Not by forcing yourself, but by returning when your mind begins to wander.

It isn’t something you either have or don’t. It’s a skill that develops with practice, and one that shapes how your time is lived.
""",
                titleTopPadding: 120
            )
        case .paywall:
            return nil
        }
    }

    @ViewBuilder
    func pageIndicator(for step: Step) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .frame(width: index == step.rawValue ? 18 : 6, height: 6)
                    .opacity(index == step.rawValue ? 0.9 : 0.35)
            }
        }
        .foregroundStyle(Color.white.opacity(0.6))
    }

    func goForward() {
        if let next = Step(rawValue: step.rawValue + 1) {
            Haptics.medium()
            if next == .paywall {
                finish()
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    step = next
                }
            }
        } else {
            finish()
        }
    }

    func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1), previous.rawValue >= 0 {
            Haptics.medium()
            withAnimation(.easeInOut(duration: 0.15)) {
                step = previous
            }
        }
    }

    func finish() {
        onFinish(Completion(requestPricing: true))
    }
}

// MARK: - Gestures

private extension OnboardingStoryView {
    @ViewBuilder
    var gestureOverlay: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: proxy.size.width * 0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { goBack() }
                Spacer()
                    .allowsHitTesting(false)
                Color.clear
                    .frame(width: proxy.size.width * 0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { goForward() }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let threshold: CGFloat = 30
                        if value.translation.width < -threshold {
                            goForward()
                        } else if value.translation.width > threshold {
                            goBack()
                        }
                    }
            )
            .ignoresSafeArea()
        }
    }
}
