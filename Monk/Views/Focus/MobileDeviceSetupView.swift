import FamilyControls
import SwiftUI

struct MobileDeviceSetupView: View {
    @ObservedObject var service: CrossDeviceFocusService
    let isPresented: Binding<Bool>?

    @State private var selection = FamilyActivitySelection()
    @State private var browsers = FamilyActivitySelection()
    @State private var defaultBlockingEnabled = false
    @State private var picker: MobileApplicationPickerKind?
    @State private var isRequestingAccess = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 44)

                Label("Monk", systemImage: "circle.hexagongrid.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Set up this device once.")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))

                    Text("Monk uses Apple’s Screen Time controls. Your focus, requested app names, and websites sync through your Apple Account; opaque Screen Time tokens stay private to each device.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                setupRow(
                    title: "Screen Time access",
                    detail: service.isScreenTimeAuthorized ? "Ready" : "Required to block everything else",
                    systemImage: service.isScreenTimeAuthorized ? "checkmark.circle.fill" : "shield.lefthalf.filled"
                ) {
                    guard !service.isScreenTimeAuthorized else { return }
                    isRequestingAccess = true
                    Task {
                        if await service.requestScreenTimeAuthorization() == false {
                            errorMessage = "Screen Time access is required for Monk to enforce a focus."
                        }
                        isRequestingAccess = false
                    }
                }

                Toggle(isOn: $defaultBlockingEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Block by default")
                            .font(.headline)
                        Text("Only always-allowed apps work outside a timed focus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.cyan)
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Always allowed apps")
                        .font(.headline)

                    MobileApplicationSearchPicker(
                        service: service,
                        selection: $selection
                    ) {
                        picker = .alwaysAllowedApps
                    }
                }

                MobileApplicationMappingSection(
                    service: service,
                    applications: service.unresolvedDefaultApplications,
                    onSaved: { mappedSelection in
                        selection.applicationTokens.formUnion(mappedSelection.applicationTokens)
                    }
                )

                setupRow(
                    title: "Browsers for allowed websites",
                    detail: browserCountLabel,
                    systemImage: "safari"
                ) {
                    picker = .browsers
                }

                HStack(spacing: 10) {
                    Image(systemName: service.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                    Text(service.syncStatus)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Finish setup") {
                    finishSetup()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(actionGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(.plain)
                .disabled(!service.isScreenTimeAuthorized || isRequestingAccess)
                .opacity(service.isScreenTimeAuthorized && !isRequestingAccess ? 1 : 0.42)

                Text(defaultBlockingEnabled
                    ? "With no exceptions, every app except Monk is blocked until you begin a timed focus."
                    : "When default blocking is off, these apps are reused as your starting focus selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(MobileFocusBackground())
        .onAppear {
            selection = service.allowedSelection()
            browsers = service.browserSelection()
            defaultBlockingEnabled = service.defaultBlockingEnabled
        }
        .sheet(item: $picker) { kind in
            MobileApplicationSelectionSheet(
                service: service,
                kind: kind,
                selection: kind == .browsers ? $browsers : $selection
            )
        }
        .alert("Setup could not finish", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var browserCountLabel: String {
        let count = browsers.applicationTokens.count
        if count == 0 { return "Optional until you allow a website" }
        return "\(count) browser\(count == 1 ? "" : "s") automatically allowed"
    }

    private var actionGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.18, green: 0.58, blue: 0.85), Color(red: 0.03, green: 0.64, blue: 0.60)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func setupRow(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func finishSetup() {
        do {
            try service.completeSetup(
                with: selection,
                browsers: browsers,
                defaultBlockingEnabled: defaultBlockingEnabled
            )
            isPresented?.wrappedValue = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
