import SwiftUI

struct MobileActiveFocusView: View {
    @ObservedObject var service: CrossDeviceFocusService
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

                    Label(service.syncStatus, systemImage: service.iCloudAvailable ? "icloud" : "icloud.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    MobileApplicationMappingSection(
                        service: service,
                        applications: applicationsToMatch
                    )

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

                    if state.endsAt <= context.date {
                        expiryDecision
                    } else {
                        Label("This focus cannot be ended early.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 680)
                .frame(minHeight: 600)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var expiryDecision: some View {
        VStack(spacing: 14) {
            Text("Session complete")
                .font(.headline)
            Text("Keep going, or return to your default access?")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                extensionButton("15m", minutes: 15)
                extensionButton("30m", minutes: 30)
                extensionButton("1h", minutes: 60)
            }

            Button("End session") {
                service.endExpiredFocus()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var applicationsToMatch: [CrossDeviceApplication] {
        let sessionApplications = service.unresolvedApplications(for: state)
        let defaultApplications = service.defaultBlockingEnabled
            ? service.unresolvedDefaultApplications
            : []
        var seen = Set<String>()
        return (sessionApplications + defaultApplications).filter {
            seen.insert($0.id).inserted
        }
    }

    private func extensionButton(_ title: String, minutes: Int) -> some View {
        Button(title) {
            service.extendExpiredFocus(by: TimeInterval(minutes * 60))
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
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
