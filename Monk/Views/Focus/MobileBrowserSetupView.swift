import FamilyControls
import SwiftUI

struct MobileBrowserSetupView: View {
    @ObservedObject var service: CrossDeviceFocusService
    let state: CrossDeviceFocusState

    @State private var browsers = FamilyActivitySelection()
    @State private var picker: MobileApplicationPickerKind?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()

            Label("Monk", systemImage: "circle.hexagongrid.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Choose your browsers once.")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))

            Text("“\(state.intention)” allows websites. Apple requires you to privately choose the browsers Monk should open; they will be included automatically from now on.")
                .foregroundStyle(.secondary)

            Button {
                picker = .browsers
            } label: {
                HStack {
                    Image(systemName: "safari")
                    Text(browserCountLabel)
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

            Button("Allow these browsers") {
                guard !browsers.applicationTokens.isEmpty else {
                    errorMessage = "Choose at least one browser."
                    return
                }
                if !service.saveBrowserSelection(browsers) {
                    errorMessage = "Monk could not save this browser selection."
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
            .disabled(browsers.applicationTokens.isEmpty)
            .opacity(browsers.applicationTokens.isEmpty ? 0.42 : 1)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .onAppear {
            browsers = service.browserSelection()
        }
        .sheet(item: $picker) { kind in
            MobileApplicationSelectionSheet(
                service: service,
                kind: kind,
                selection: $browsers
            )
        }
        .alert("Browsers are required", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var browserCountLabel: String {
        let count = browsers.applicationTokens.count
        return count == 0 ? "Choose browsers" : "\(count) browser\(count == 1 ? "" : "s") selected"
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
