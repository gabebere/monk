import SwiftUI

struct OnboardingStoryView: View {
    struct Scene: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let body: String
    }

    let onFinish: () -> Void

    @State private var page = 0

    private let scenes: [Scene] = [
        Scene(
            id: 0,
            symbol: "scope",
            title: "Pick what matters.",
            body: "Create a project, define one task, and point your attention there."
        ),
        Scene(
            id: 1,
            symbol: "eye.trianglebadge.exclamationmark",
            title: "Protect your attention.",
            body: "Monk helps you reduce distractions so your time stays on purpose."
        ),
        Scene(
            id: 2,
            symbol: "chart.line.uptrend.xyaxis",
            title: "Let focus compound.",
            body: "Every session is tracked to your project and synced to calendar so progress is visible."
        )
    ]

    var body: some View {
        ZStack {
            AnimatingBackground()
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 48)

                TabView(selection: $page) {
                    ForEach(Array(scenes.enumerated()), id: \.offset) { index, scene in
                        OnboardingSceneCard(scene: scene, isActive: page == index)
                            .tag(index)
                            .padding(.horizontal, 4)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: 440)

                HStack(spacing: 6) {
                    ForEach(0..<scenes.count, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(index == page ? 0.92 : 0.35))
                            .frame(width: index == page ? 20 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: page)

                Button(action: advance) {
                    Text(page == scenes.count - 1 ? "Continue" : "Next")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.large)
                .tint(Color.white.opacity(0.22))
                .foregroundStyle(.white)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }

    private func advance() {
        if page < scenes.count - 1 {
            Haptics.medium()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                page += 1
            }
            return
        }
        Haptics.heavy()
        onFinish()
    }
}

private struct OnboardingSceneCard: View {
    let scene: OnboardingStoryView.Scene
    let isActive: Bool

    @State private var drift = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 122, height: 122)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )

                Image(systemName: scene.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: isActive)
            }
            .scaleEffect(isActive ? 1.0 : 0.94)
            .offset(y: drift ? -4 : 4)
            .opacity(isActive ? 1 : 0.82)
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: drift)
            .animation(.spring(response: 0.35, dampingFraction: 0.88), value: isActive)

            Text(scene.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text(scene.body)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.84))
                .lineSpacing(4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .onAppear {
            drift = true
        }
    }
}
