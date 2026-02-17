import SwiftUI
import UIKit

enum GuidedTutorialStep: Int, CaseIterable {
    case createProject
    case createTask
    case startFocus

    var title: String {
        switch self {
        case .createProject:
            return "Create Your First Project"
        case .createTask:
            return "Create Your First Task"
        case .startFocus:
            return "Start Your First Focus"
        }
    }

    var message: String {
        switch self {
        case .createProject:
            return "Use + or New Project on Home. Keep it simple and save your first project."
        case .createTask:
            return "Now on Home, create one task linked to your project."
        case .startFocus:
            return "Tap Time to focus, or select your task first and then tap Time to focus. Monk will track time to the project and log it to calendar."
        }
    }

    var progressText: String {
        "Step \(rawValue + 1) of \(Self.allCases.count)"
    }
}

enum GuidedTutorialAnchor: Hashable {
    case projectsAddButton
    case projectsEmptyCreateButton
    case homeNewTaskButton
    case homeEmptyNewTaskButton
    case homeFirstTaskRow
    case homeTimeToFocusButton
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
    let blocksTouchesOutsideHoles: Bool
    let onSkip: () -> Void

    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .top) {
            if blocksTouchesOutsideHoles {
                TutorialTouchShield(holes: holes)
                    .ignoresSafeArea()
            }

            TutorialMaskShape(holes: holes)
                .fill(Color.black.opacity(0.64), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ForEach(Array(holes.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: 2)
                    .frame(width: rect.width + 16, height: rect.height + 16)
                    .position(x: rect.midX, y: rect.midY)
                    .scaleEffect(pulse ? 1.03 : 0.98)
                    .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: pulse)
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
            .padding(.horizontal, 16)
            .padding(.top, topInset + 16)
        }
        .onAppear {
            pulse = true
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
        uiView.holes = holes.map { $0.insetBy(dx: -8, dy: -8) }
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

private struct TutorialMaskShape: Shape {
    let holes: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        for hole in holes {
            let expanded = hole.insetBy(dx: -8, dy: -8)
            path.addRoundedRect(in: expanded, cornerSize: CGSize(width: 18, height: 18))
        }
        return path
    }
}
