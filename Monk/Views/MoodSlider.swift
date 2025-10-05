import SwiftUI

struct MoodSlider: View {
    @Binding var value: Int
    private let moods: [MoodOption] = [
        .init(index: 0, emoji: "😞", label: "Bad", tint: Color.red.opacity(0.75)),
        .init(index: 1, emoji: "😐", label: "Neutral", tint: Color.orange.opacity(0.7)),
        .init(index: 2, emoji: "😄", label: "Good", tint: Color.green.opacity(0.75))
    ]

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let fraction = CGFloat(value) / CGFloat(max(moods.count - 1, 1))

                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: moods.map { $0.tint }, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(44, geo.size.width * fraction))
                            .opacity(0.55)
                            .animation(.easeOut(duration: 0.25), value: value)
                    }
                    .overlay {
                        Slider(value: Binding(
                            get: { Double(value) },
                            set: { newVal in
                                let rounded = Int(newVal.rounded())
                                guard rounded != value else { return }
                                value = rounded
                            }
                        ), in: 0...Double(moods.count - 1), step: 1, onEditingChanged: { editing in
                            if !editing { triggerHaptic(for: value) }
                        })
                        .tint(.white)
                        .padding(.horizontal, 18)
                    }
            }
            .frame(height: 44)

            HStack {
                ForEach(moods) { mood in
                    VStack(spacing: 4) {
                        Text(mood.emoji)
                            .font(.title3)
                            .scaleEffect(value == mood.index ? 1.2 : 1.0)
                            .shadow(color: mood.tint.opacity(value == mood.index ? 0.6 : 0), radius: 6)
                        Text(mood.label)
                            .font(.caption2)
                            .fontWeight(value == mood.index ? .semibold : .regular)
                            .foregroundStyle(value == mood.index ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: value)
    }
}

private struct MoodOption: Identifiable {
    let index: Int
    let emoji: String
    let label: String
    let tint: Color
    var id: Int { index }
}

private extension MoodSlider {
    func triggerHaptic(for moodIndex: Int) {
        switch moodIndex {
        case 0: Haptics.moodSoft()
        case 1: Haptics.moodMedium()
        default: Haptics.moodStrong()
        }
    }
}
