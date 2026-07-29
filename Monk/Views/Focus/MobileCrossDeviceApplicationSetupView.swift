import FamilyControls
import SwiftUI

struct MobileCrossDeviceApplicationSetupView: View {
    @ObservedObject var service: CrossDeviceFocusService
    let application: CrossDeviceApplication

    @State private var selection = FamilyActivitySelection()
    @State private var isShowingPicker = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()

            Label("Monk", systemImage: "circle.hexagongrid.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Match \(application.displayName) once.")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))

            Text("This focus allows \(application.displayName) on your Mac. Apple keeps Screen Time app identities private, so choose its counterpart on this iPhone. Monk remembers the local match without uploading its token.")
                .foregroundStyle(.secondary)

            Button {
                isShowingPicker = true
            } label: {
                HStack {
                    Image(systemName: "app.badge.checkmark")
                    Text(selectionLabel)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button("Use this app") {
                guard selection.applicationTokens.count == 1 else {
                    errorMessage = "Choose exactly one app: \(application.displayName)."
                    return
                }
                if !service.saveApplicationMapping(selection, for: application) {
                    errorMessage = "Monk could not save this private app match."
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.58, blue: 0.85), Color(red: 0.03, green: 0.64, blue: 0.60)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .buttonStyle(.plain)
            .disabled(selection.applicationTokens.count != 1)
            .opacity(selection.applicationTokens.count == 1 ? 1 : 0.42)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                FamilyActivityPicker(
                    headerText: "Choose only \(application.displayName) on this iPhone.",
                    footerText: "This private Screen Time token remains on this device.",
                    selection: $selection
                )
                .navigationTitle(application.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isShowingPicker = false
                        }
                    }
                }
            }
        }
        .alert("App match needed", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var selectionLabel: String {
        switch selection.applicationTokens.count {
        case 0:
            "Choose \(application.displayName)"
        case 1:
            "One app selected"
        default:
            "Choose only one app"
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
