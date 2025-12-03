import SwiftUI

struct TutorialAnchorPreference: Equatable {
    let stage: TutorialStage
    let frame: CGRect
    let cornerRadius: CGFloat
}

struct TutorialAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialAnchorPreference] = []

    static func reduce(value: inout [TutorialAnchorPreference], nextValue: () -> [TutorialAnchorPreference]) {
        value.append(contentsOf: nextValue())
    }
}

private struct TutorialAnchorModifier: ViewModifier {
    let stage: TutorialStage
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TutorialAnchorPreferenceKey.self,
                    value: [
                        TutorialAnchorPreference(
                            stage: stage,
                            frame: proxy.frame(in: .global),
                            cornerRadius: cornerRadius
                        )
                    ]
                )
            }
        )
    }
}

extension View {
    func tutorialAnchor(_ stage: TutorialStage, cornerRadius: CGFloat = 18) -> some View {
        modifier(TutorialAnchorModifier(stage: stage, cornerRadius: cornerRadius))
    }
}

struct TutorialOverlayView: View {
    let stage: TutorialStage
    let highlight: TutorialHighlightInfo?
    let onNext: () -> Void
    let onSkip: () -> Void
    var showActions: Bool = true

    var body: some View {
        GeometryReader { proxy in
            dimmingLayer(in: proxy)
                .allowsHitTesting(false)
                .overlay(alignment: .bottom) {
                    overlayContent
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 32)
                }
                .ignoresSafeArea()
        }
        .transition(.opacity)
    }

    private var overlayContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Text(stage.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                Text(stage.message)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
            }
            if showActions {
                HStack(spacing: 12) {
                    if !stage.isLast {
                        Button(action: {
                            Haptics.heavy()
                            onSkip()
                        }) {
                            Text("Skip tutorial")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
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
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        Haptics.heavy()
                        onNext()
                    }) {
                        Text(stage.isLast ? "Finish" : "Next")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
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
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [
                        Color(red: 0.20, green: 0.24, blue: 0.48),
                        Color(red: 0.12, green: 0.32, blue: 0.62),
                        Color(red: 0.07, green: 0.54, blue: 0.68)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    private func dimmingLayer(in proxy: GeometryProxy) -> some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.black.opacity(0.65))
            )

            guard let highlight else { return }
            let rect = highlight.frame
            let rounded = RoundedRectangle(cornerRadius: highlight.cornerRadius, style: .continuous)
                .path(in: CGRect(x: rect.origin.x,
                                 y: rect.origin.y,
                                 width: rect.size.width,
                                 height: rect.size.height))
            context.addFilter(.alphaThreshold(min: 0.01, max: 1))
            context.blendMode = .destinationOut
            context.fill(rounded, with: .color(.white))
        }
    }
}
