import FamilyControls
import SwiftUI

struct MobileApplicationMappingSheet: View {
    @ObservedObject var service: CrossDeviceFocusService
    let application: CrossDeviceApplication
    var onSaved: (FamilyActivitySelection) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var selection = FamilyActivitySelection()
    @State private var showingSaveError = false

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(
                headerText: "Choose the app on this device that corresponds to \(application.displayName).",
                footerText: "Choose exactly one app. This match stays on this device and is reused when another device allows \(application.displayName).",
                selection: $selection
            )
            .navigationTitle("Match \(application.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save match") {
                        if service.saveApplicationMapping(for: application, selection: selection) {
                            onSaved(selection)
                            dismiss()
                        } else {
                            showingSaveError = true
                        }
                    }
                    .disabled(!hasOneApplication)
                }
            }
            .alert("Match could not be saved", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Select one app, without categories or websites, and try again.")
            }
        }
    }

    private var hasOneApplication: Bool {
        selection.applicationTokens.count == 1
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
    }
}
