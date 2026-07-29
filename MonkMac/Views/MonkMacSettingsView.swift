import SwiftUI

struct MonkMacSettingsView: View {
    var body: some View {
        Form {
            Section("Enforcement") {
                LabeledContent("Application guardian", value: "Active during focus")
                LabeledContent("Process authorization", value: "Endpoint Security pending")
                LabeledContent("Website guardian", value: "Safari and Chromium")
                LabeledContent("Network-wide filtering", value: "System Extension pending")
            }

            Section {
                Text("Monk checks the active browser tab during focus and restores the last allowed page when needed. macOS will ask for browser-control permission the first time. System-extension enforcement can later extend this to all network traffic.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 330)
    }
}
