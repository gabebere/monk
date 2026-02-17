import SwiftUI

struct MinimalFocusHeroView: View {
    let model: HeroModel
    var onCalmLaneTap: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.21, green: 0.40, blue: 0.76),
                            Color(red: 0.16, green: 0.29, blue: 0.59),
                            Color(red: 0.12, green: 0.52, blue: 0.63)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.cyan.opacity(0.36))
                .frame(width: 180, height: 180)
                .blur(radius: 34)
                .offset(x: 44, y: -64)

            Image(systemName: "scope")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.86))
                .padding(14)
                .background(Color.white.opacity(0.14), in: Circle())
                .padding(14)

            VStack(alignment: .leading, spacing: 12) {
                Text(model.focusedTodayText)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)

                Text("Focused today")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))

                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption.weight(.bold))
                    Text("Total with Monk: \(model.totalWithMonkText)")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Color.white.opacity(0.82))

                if let calmLaneText = model.calmLaneText {
                    calmLaneChip(text: calmLaneText)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private func calmLaneChip(text: String) -> some View {
        if let onCalmLaneTap {
            Button(action: onCalmLaneTap) {
                chipLabel(text: text)
            }
            .buttonStyle(.plain)
        } else {
            chipLabel(text: text)
        }
    }

    private func chipLabel(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.16), in: Capsule())
    }
}
