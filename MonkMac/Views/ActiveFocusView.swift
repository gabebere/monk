import AppKit
import SwiftUI

struct ActiveFocusView: View {
    @ObservedObject var store: FocusSessionStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 18) {
                if let policy = store.activePolicy {
                    VStack(spacing: 6) {
                        Text(policy.intention)
                            .font(.system(size: 29, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        Text(store.remainingTimeLabel)
                            .font(.system(size: 56, weight: .light, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary.opacity(0.92))
                            .contentTransition(.numericText())
                    }

                    if !policy.allowedApplications.isEmpty {
                        applicationChips(policy.allowedApplications)
                    }
                }

                blockedActivity
            }

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Text("This focus ends when the timer reaches zero.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Hide Monk", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.76))
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.primary.opacity(0.07), lineWidth: 1)
                    }
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
    }

    private func applicationChips(
        _ applications: [ApplicationDescriptor]
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            applicationChipRow(applications)
                .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                applicationChipRow(applications)
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func applicationChipRow(
        _ applications: [ApplicationDescriptor]
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(applications) { application in
                ActiveApplicationChip(application: application)
            }
        }
    }

    @ViewBuilder
    private var blockedActivity: some View {
        if let name = store.lastBlockedApplicationName {
            blockedChip("Blocked \(name)", systemImage: "hand.raised.fill")
        } else if let website = store.lastBlockedWebsite {
            blockedChip("Blocked \(website)", systemImage: "globe")
        }
    }

    private func blockedChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.primary.opacity(0.07), in: Capsule())
    }
}

private struct ActiveApplicationChip: View {
    let application: ApplicationDescriptor

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.bundleURL.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)

            Text(application.displayName)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary.opacity(0.82))
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(.primary.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
