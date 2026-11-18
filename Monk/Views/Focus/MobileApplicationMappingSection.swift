import FamilyControls
import SwiftUI

struct MobileApplicationMappingSection: View {
    @ObservedObject var service: CrossDeviceFocusService
    let applications: [CrossDeviceApplication]
    var onSaved: (FamilyActivitySelection) -> Void = { _ in }

    @State private var selectedApplication: CrossDeviceApplication?

    var body: some View {
        if !applications.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Match apps on this device")
                    .font(.headline)

                Text("Choose the local app for each allowed app from another device. If it is not installed here, leave it unmatched. Unmatched apps stay blocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(applications) { application in
                    Button {
                        selectedApplication = application
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "app.badge.checkmark")
                            Text(application.displayName)
                                .lineLimit(2)
                            Spacer()
                            Text("Choose app")
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.primary)
                        .padding(14)
                        .frame(minHeight: 50)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose local app for \(application.displayName)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(item: $selectedApplication) { application in
                MobileApplicationMappingSheet(
                    service: service,
                    application: application,
                    onSaved: onSaved
                )
            }
        }
    }
}
