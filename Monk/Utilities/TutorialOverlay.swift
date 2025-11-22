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
            HStack(spacing: 12) {
                Button(action: {
                    Haptics.heavy()
                    onSkip()
                }) {
                    Text("Skip tutorial")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: {
                    Haptics.heavy()
                    onNext()
                }) {
                    Text(stage.isLast ? "Finish" : "Next")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.9), in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
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
