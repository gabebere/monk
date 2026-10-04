import FamilyControls
import SwiftUI

private enum MobileFocusField: Hashable {
    case intention
    case website
}

struct MobileFocusComposerView: View {
    @ObservedObject var service: CrossDeviceFocusService

    @State private var intention = ""
    @State private var hours = 0
    @State private var minutes = 0
    @State private var allowedSelection = FamilyActivitySelection()
    @State private var allowedMacApplications: [CrossDeviceApplication] = []
    @State private var allowedBrowsers = FamilyActivitySelection()
    @State private var allowedDomains: [String] = []
    @State private var website = ""
    @State private var picker: MobileApplicationPickerKind?
    @State private var showingCommitmentConfirmation = false
    @State private var isStarting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: MobileFocusField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Label("Monk", systemImage: "circle.hexagongrid.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                TextField("What are you doing now?", text: $intention, axis: .vertical)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .intention)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }

                durationSection
                allowedAppsSection
                allowedWebsitesSection

                Label(
                    "Every app and website you do not allow will be blocked until the timer reaches zero.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(action: prepareToBegin) {
                    HStack {
                        if isStarting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Begin focus")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(actionGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canBegin || isStarting)
                .opacity(canBegin && !isStarting ? 1 : 0.42)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            allowedSelection = service.defaultBlockingEnabled
                ? FamilyActivitySelection()
                : service.allowedSelection()
            allowedBrowsers = service.browserSelection()
        }
        .sheet(item: $picker) { kind in
            MobileApplicationSelectionSheet(
                service: service,
                kind: kind,
                selection: kind == .browsers ? $allowedBrowsers : $allowedSelection
            )
        }
        .confirmationDialog(
            "This focus cannot be ended early",
            isPresented: $showingCommitmentConfirmation,
            titleVisibility: .visible
        ) {
            Button("Begin for \(durationLabel)") {
                Task { await beginFocus() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(service.defaultBlockingEnabled
                ? "Your always-allowed apps and the apps shown here will remain available until the timer reaches zero."
                : "Only the apps and websites shown here will remain available until the timer reaches zero.")
        }
        .alert("Monk could not begin focus", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("For")
            HStack(spacing: 10) {
                durationWheel(
                    title: "Hours",
                    suffix: "h",
                    values: 0...99,
                    selection: $hours
                )
                durationWheel(
                    title: "Minutes",
                    suffix: "m",
                    values: 0...59,
                    selection: $minutes
                )
            }
        }
    }

    private var allowedAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Allowed apps")

            MobileApplicationSearchPicker(
                service: service,
                selection: $allowedSelection,
                macSelection: $allowedMacApplications
            ) {
                focusedField = nil
                picker = .allowedApps
            }

            if service.defaultBlockingEnabled {
                Text("Your always-allowed apps are included automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var allowedWebsitesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Allowed websites")

            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                TextField("example.com", text: $website)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .website)
                    .onSubmit(addWebsite)
                Button(action: addWebsite) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Allow website")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !allowedDomains.isEmpty {
                Label(browserCountLabel, systemImage: "safari")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allowedDomains, id: \.self) { domain in
                            Button {
                                allowedDomains.removeAll { $0 == domain }
                            } label: {
                                HStack(spacing: 7) {
                                    Text(domain)
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.bold))
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(domain)")
                        }
                    }
                }
            }
        }
    }

    private var durationMinutes: Int {
        hours * 60 + minutes
    }

    private var canBegin: Bool {
        !intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && durationMinutes > 0
    }

    private var durationLabel: String {
        let hourCount = durationMinutes / 60
        let minuteCount = durationMinutes % 60
        if hourCount == 0 { return "\(minuteCount)m" }
        if minuteCount == 0 { return "\(hourCount)h" }
        return "\(hourCount)h \(minuteCount)m"
    }

    private var browserCountLabel: String {
        let count = allowedBrowsers.applicationTokens.count
        return count == 0
            ? "Choose your browsers once"
            : "\(count) browser\(count == 1 ? " is" : "s are") automatically allowed"
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func durationWheel(
        title: String,
        suffix: String,
        values: ClosedRange<Int>,
        selection: Binding<Int>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(values), id: \.self) { value in
                Text("\(value) \(suffix)")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 116, height: 112)
        .clipped()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityLabel(title)
    }

    private func addWebsite() {
        guard let domain = MobileFocusInput.normalizedDomain(website) else {
            if !website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Enter a complete domain such as example.com."
            }
            return
        }
        if !allowedDomains.contains(domain) {
            allowedDomains.append(domain)
        }
        website = ""
        if allowedBrowsers.applicationTokens.isEmpty {
            focusedField = nil
            picker = .browsers
        }
    }

    private func prepareToBegin() {
        focusedField = nil
        if !website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addWebsite()
            guard errorMessage == nil else { return }
        }
        guard allowedDomains.isEmpty || !allowedBrowsers.applicationTokens.isEmpty else {
            picker = .browsers
            return
        }
        showingCommitmentConfirmation = true
    }

    @MainActor
    private func beginFocus() async {
        guard canBegin else { return }
        isStarting = true
        defer { isStarting = false }

        do {
            try await service.beginFocus(
                intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
                duration: TimeInterval(durationMinutes * 60),
                allowedSelection: allowedSelection,
                allowedBrowsers: allowedBrowsers,
                allowedDomains: allowedDomains,
                allowedApplications: allowedMacApplications
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
