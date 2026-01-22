import SwiftUI
import RevenueCatUI
import RevenueCat

struct RevenueCatPaywallView: View {
    @EnvironmentObject private var revenueCat: RevenueCatService
    @EnvironmentObject private var entitlementSync: EntitlementSyncService
    @Environment(\.dismiss) private var dismiss

    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let offering = revenueCat.activeOffering {
                    PaywallView(offering: offering)
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
                    if canDismiss {
                        Button("Close") {
                            onClose()
                            dismiss()
                        }
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

    private var canDismiss: Bool {
        revenueCat.isPro || entitlementSync.isEntitled
    }
}
