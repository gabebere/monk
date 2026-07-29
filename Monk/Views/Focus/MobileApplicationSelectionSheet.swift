import FamilyControls
import SwiftUI

enum MobileApplicationPickerKind: String, Identifiable {
    case allowedApps
    case browsers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allowedApps: "Allowed apps"
        case .browsers: "Browsers"
        }
    }

    var header: String {
        switch self {
        case .allowedApps:
            "Choose the apps that should remain available during focus."
        case .browsers:
            "Choose Safari, Chrome, or any other browser you use."
        }
    }

    var footer: String {
        switch self {
        case .allowedApps:
            "Monk will block everything else until the timer ends."
        case .browsers:
            "Monk remembers these and allows them automatically whenever your focus includes websites."
        }
    }
}

struct MobileApplicationSelectionSheet: View {
    @ObservedObject var service: CrossDeviceFocusService
    let kind: MobileApplicationPickerKind
    @Binding var selection: FamilyActivitySelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if service.searchableApplications.isEmpty {
                    FamilyActivityPicker(
                        headerText: kind.header,
                        footerText: kind.footer,
                        selection: $selection
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(kind.header)
                                .foregroundStyle(.secondary)

                            MobileApplicationSearchPicker(
                                service: service,
                                selection: $selection,
                                openSystemPicker: {}
                            )
                        }
                        .padding(20)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
