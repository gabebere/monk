import FamilyControls
import SwiftUI

enum MobileApplicationPickerKind: String, Identifiable {
    case allowedApps
    case alwaysAllowedApps
    case browsers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allowedApps: "Allowed apps"
        case .alwaysAllowedApps: "Always allowed"
        case .browsers: "Browsers"
        }
    }

    var header: String {
        switch self {
        case .allowedApps:
            "Choose the apps that should remain available during focus."
        case .alwaysAllowedApps:
            "Choose the few apps that should remain available between focus sessions."
        case .browsers:
            "Choose Safari, Chrome, or any other browser you use."
        }
    }

    var footer: String {
        switch self {
        case .allowedApps:
            "Monk will block everything else until the timer ends."
        case .alwaysAllowedApps:
            "When default blocking is on, every other app requires a timed focus session."
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
            FamilyActivityPicker(
                headerText: kind.header,
                footerText: kind.footer,
                selection: $selection
            )
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
