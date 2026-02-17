import SwiftUI

struct TodayRhythmStripView: View {
    let model: TodayRhythmModel

    private var maxMinuteValue: Int {
        max(model.hourlyMinutes.max() ?? 0, 1)
    }

    private var peakHour: Int? {
        guard let maxValue = model.hourlyMinutes.max(),
              maxValue > 0,
              let idx = model.hourlyMinutes.firstIndex(of: maxValue) else {
            return nil
        }
        return idx
    }

    var body: some View {
        InsightCardContainer(
            colors: [
                Color(red: 0.11, green: 0.24, blue: 0.50),
                Color(red: 0.12, green: 0.34, blue: 0.42)
            ],
            glow: Color(red: 0.45, green: 0.84, blue: 0.94),
            strokeColor: Color.cyan.opacity(0.38)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text(model.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))

                    Spacer()

                    if let peakHour {
                        Text("Peak \(String(format: "%02d", peakHour)):00")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                }

                Text(model.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(model.hourlyMinutes.enumerated()), id: \.offset) { hour, minuteValue in
                            let heightFraction = CGFloat(minuteValue) / CGFloat(maxMinuteValue)
                            let isPeak = hour == peakHour
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: isPeak
                                            ? [Color.white, Color.cyan]
                                            : [Color.white.opacity(minuteValue > 0 ? 0.78 : 0.22), Color.cyan.opacity(minuteValue > 0 ? 0.55 : 0.14)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: max(4, 42 * heightFraction))
                        }
                    }
                    .frame(height: 46)

                    HStack {
                        Text("00")
                        Spacer()
                        Text("06")
                        Spacer()
                        Text("12")
                        Spacer()
                        Text("18")
                        Spacer()
                        Text("23")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.60))
                }

                Text(model.actionHint)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(1)
            }
        }
    }
}
