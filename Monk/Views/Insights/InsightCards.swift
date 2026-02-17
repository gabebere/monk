import SwiftUI

struct InsightCardContainer<Content: View>: View {
    var colors: [Color] = [Color.white.opacity(0.14), Color.white.opacity(0.08)]
    var glow: Color = .clear
    var strokeColor: Color = Color.white.opacity(0.16)
    let content: Content

    init(
        colors: [Color] = [Color.white.opacity(0.14), Color.white.opacity(0.08)],
        glow: Color = .clear,
        strokeColor: Color = Color.white.opacity(0.16),
        @ViewBuilder content: () -> Content
    ) {
        self.colors = colors
        self.glow = glow
        self.strokeColor = strokeColor
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            Circle()
                .fill(glow.opacity(0.30))
                .frame(width: 140, height: 140)
                .blur(radius: 24)
                .offset(x: 48, y: -52)

            content
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }
}

struct InsightTextCardView: View {
    let model: InsightCardModel

    var body: some View {
        let style = InsightVisualStyle.style(for: model.title)

        InsightCardContainer(
            colors: style.background,
            glow: style.glow,
            strokeColor: style.glow.opacity(0.45)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: style.icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(style.glow)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.14), in: Circle())

                        Text(model.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                    }

                    Spacer(minLength: 0)

                    CardSparkBars(color: style.glow)
                }

                Text(model.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.85)

                Text(model.subheadline)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.actionHint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
        }
    }
}

struct BottomInsightCardView: View {
    let model: BottomSectionModel

    var body: some View {
        switch model {
        case .weeklyPace(let weekly):
            InsightTextCardView(
                model: InsightCardModel(
                    title: weekly.title,
                    headline: weekly.headline,
                    subheadline: weekly.subheadline,
                    actionHint: weekly.actionHint
                )
            )
        case .consistency(let consistency):
            InsightTextCardView(
                model: InsightCardModel(
                    title: consistency.title,
                    headline: consistency.headline,
                    subheadline: consistency.subheadline,
                    actionHint: consistency.actionHint
                )
            )
        }
    }
}

private struct CardSparkBars: View {
    let color: Color

    private let heights: [CGFloat] = [16, 22, 30, 18, 34, 24]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(0.72))
                    .frame(width: 5, height: height)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct InsightVisualStyle {
    let icon: String
    let background: [Color]
    let glow: Color

    static func style(for title: String) -> InsightVisualStyle {
        switch title {
        case "Best focus window":
            return InsightVisualStyle(
                icon: "clock.badge.checkmark",
                background: [Color(red: 0.16, green: 0.34, blue: 0.62), Color(red: 0.11, green: 0.21, blue: 0.45)],
                glow: Color(red: 0.47, green: 0.80, blue: 1.00)
            )
        case "Momentum":
            return InsightVisualStyle(
                icon: "waveform.path.ecg",
                background: [Color(red: 0.20, green: 0.38, blue: 0.56), Color(red: 0.13, green: 0.26, blue: 0.38)],
                glow: Color(red: 0.43, green: 0.91, blue: 0.75)
            )
        case "Follow-through":
            return InsightVisualStyle(
                icon: "checklist.checked",
                background: [Color(red: 0.39, green: 0.27, blue: 0.47), Color(red: 0.26, green: 0.18, blue: 0.35)],
                glow: Color(red: 0.94, green: 0.68, blue: 0.96)
            )
        case "Weekly pace":
            return InsightVisualStyle(
                icon: "gauge.with.dots.needle.50percent",
                background: [Color(red: 0.29, green: 0.41, blue: 0.28), Color(red: 0.19, green: 0.27, blue: 0.21)],
                glow: Color(red: 0.67, green: 0.90, blue: 0.67)
            )
        case "Consistency snapshot":
            return InsightVisualStyle(
                icon: "flame.fill",
                background: [Color(red: 0.50, green: 0.29, blue: 0.24), Color(red: 0.33, green: 0.19, blue: 0.16)],
                glow: Color(red: 1.00, green: 0.72, blue: 0.54)
            )
        default:
            return InsightVisualStyle(
                icon: "sparkles",
                background: [Color.white.opacity(0.14), Color.white.opacity(0.08)],
                glow: Color.white
            )
        }
    }
}
