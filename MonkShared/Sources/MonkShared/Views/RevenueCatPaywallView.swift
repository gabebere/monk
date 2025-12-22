import SwiftUI
import RevenueCat
#if canImport(RevenueCatUI)
import RevenueCatUI
#endif

public struct RevenueCatPaywallView: View {
    @EnvironmentObject private var revenueCat: RevenueCatService
    @Environment(\.dismiss) private var dismiss

    public let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let offering = revenueCat.activeOffering {
                    paywallContent(for: offering)
                        .onAppear {
                            Analytics.track("paywall_viewed", [
                                "offering_id": offering.identifier,
                                "has_paywall": offering.paywall != nil,
                                "entitlement_active": revenueCat.isPro
                            ])
                        }
                } else {
                    VStack(spacing: 16) {
                        if revenueCat.isLoading {
                            ProgressView("Loading offers…")
                                .tint(.white)
                        } else {
                            Text("Fetching offers…")
                                .foregroundStyle(.secondary)
                            Button {
                                revenueCat.refresh()
                            } label: {
                                Text("Retry")
                                    .font(.headline.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                        dismiss()
                    }
                }
            }
            .task {
                if revenueCat.offerings == nil {
                    revenueCat.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private func paywallContent(for offering: Offering) -> some View {
        #if canImport(RevenueCatUI)
        PaywallView(offering: offering)
        #else
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Monk Pro")
                    .font(.largeTitle.bold())
                Text("Unlock all focus insights and blocking.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(offering.availablePackages, id: \.identifier) { package in
                    Button {
                        Task { await revenueCat.purchase(package: package) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(package.storeProduct.localizedTitle)
                                    .font(.headline.weight(.semibold))
                                Text(package.storeProduct.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(package.storeProduct.localizedPriceString)
                                .font(.headline.weight(.semibold))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Restore Purchases") {
                Task { await revenueCat.restore() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        #endif
    }
}
