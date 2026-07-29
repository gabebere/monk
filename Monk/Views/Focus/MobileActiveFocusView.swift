import SwiftUI

struct MobileActiveFocusView: View {
    let state: CrossDeviceFocusState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 54)

                    Capsule()
                        .fill(accent)
                        .frame(width: 72, height: 4)

                    VStack(spacing: 8) {
                        Text(state.intention)
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center)

                        Text(remainingTime(at: context.date))
                            .font(.system(size: 58, weight: .light, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                    }

                    Text("You chose what matters right now. Everything else can wait.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)

                    if !state.allowedDomains.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(state.allowedDomains, id: \.self) { domain in
                                    Label(domain, systemImage: "globe")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .background(.thinMaterial, in: Capsule())
                                }
                            }
                        }
                    }

                    Spacer(minLength: 64)

                    Label("This focus cannot be ended early.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 680)
                .frame(minHeight: 600)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var accent: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.60, blue: 0.92),
                Color(red: 0.47, green: 0.34, blue: 0.88),
                Color(red: 0.02, green: 0.67, blue: 0.58)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func remainingTime(at date: Date) -> String {
        let seconds = max(0, Int(state.endsAt.timeIntervalSince(date).rounded(.up)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
