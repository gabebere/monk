import SwiftUI
import SwiftData
import FamilyControls
import ManagedSettings
import UIKit

struct IntentSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager

    let dismiss: () -> Void
    let onSaved: (() -> Void)?

    @State private var managedApps = FamilyActivitySelection()
    @State private var alwaysAllowedTokens = Set<ManagedSettings.ApplicationToken>()
    @State private var isSaving = false
    @State private var showPicker = false
    @State private var showingAlwaysAllowedPicker = false
    @State private var authDenied = false

    private var prefs: Preferences {
        if let existing = try? modelContext.fetch(FetchDescriptor<Preferences>()).first {
            return existing
        }
        let created = Preferences(hasConvertedDailyGoal: true)
        modelContext.insert(created)
        return created
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
#if targetEnvironment(simulator)
                simulatorWarning
#else
                selectionSection(title: "Managed apps",
                                 subtitle: "Pick the apps Monk is allowed to manage and unlock. Select all apps you want Monk to control.",
                                 buttonLabel: "Select Apps",
                                 countLabel: selectedCountLabel(managedApps))

                Button {
                    showingAlwaysAllowedPicker = true
                } label: {
                    VStack(spacing: 6) {
                        Text("Always allowed apps")
                            .font(.headline.weight(.semibold))
                        Text(alwaysAllowedSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .disabled(managedApps.applicationTokens.isEmpty)
                .opacity(managedApps.applicationTokens.isEmpty ? 0.6 : 1)

                if authDenied {
                    VStack(spacing: 8) {
                        Text("Screen Time permission is required to choose apps.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        Button("Open Settings") {
                            openScreenTimeSettings()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal)
                }

#endif
            }
            .navigationTitle("Intent Mode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await saveSelections() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear { loadSelections() }
            .familyActivityPicker(isPresented: $showPicker, selection: $managedApps)
            .onChange(of: managedApps) { _, _ in
                syncAlwaysAllowedTokens()
            }
            .sheet(isPresented: $showingAlwaysAllowedPicker) {
                ManagedAppsSelectionView(
                    title: "Always Allowed",
                    subtitle: "These apps stay accessible even when Intent Mode blocks everything else.",
                    availableTokens: managedApps.applicationTokens,
                    selectedTokens: $alwaysAllowedTokens,
                    onDone: { showingAlwaysAllowedPicker = false },
                    onCancel: { showingAlwaysAllowedPicker = false }
                )
            }
        }
    }
}

private extension IntentSetupView {
    var simulatorWarning: some View {
        VStack(spacing: 16) {
            Text("App selection unavailable in Simulator")
                .font(.headline)
            Text("Run on a physical device with Screen Time enabled to pick apps for Intent Mode.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    func loadSelections() {
        managedApps = decodeSelection(from: prefs.baselineManagedAppsSelectionData) ?? FamilyActivitySelection()
        alwaysAllowedTokens = ManagedAppTokenCodec.decodeSelectionTokens(from: prefs.baselineAlwaysAllowedManagedSelectionData)
        syncAlwaysAllowedTokens()
    }

    func saveSelections() async {
        await MainActor.run { isSaving = true }
        syncAlwaysAllowedTokens()
        prefs.baselineManagedAppsSelectionData = encodeSelection(managedApps)
        prefs.baselineAlwaysAllowedManagedSelectionData = ManagedAppTokenCodec.encodeSelection(from: alwaysAllowedTokens)
        modelContext.saveOrRollback()
        IntentAppIndexStore.rebuild(from: prefs.baselineManagedAppsSelectionData)

        await MainActor.run {
            applyShields()
            isSaving = false
            dismiss()
            onSaved?()
        }
    }

    func selectedCountLabel(_ selection: FamilyActivitySelection) -> String {
        let count = selection.applicationTokens.count
        return count == 0 ? "No apps selected" : "\(count) app\(count == 1 ? "" : "s") selected"
    }

    var alwaysAllowedSummary: String {
        let count = alwaysAllowedTokens.count
        return count == 0 ? "No always-allowed apps" : "\(count) app\(count == 1 ? "" : "s") always allowed"
    }

    func openScreenTimeSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func encodeSelection(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }

    func decodeSelection(from data: Data?) -> FamilyActivitySelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    func applyShields() {
        let projectSelection = focus.currentSession?.project?.hardBlockSelectionData.flatMap(HardBlockManager.shared.decodeSelection(from:))
        IntentBlockManager.shared.applyShields(
            preferences: prefs,
            activeProjectSelection: projectSelection
        )
    }

    func syncAlwaysAllowedTokens() {
        let managedSet = managedApps.applicationTokens
        if alwaysAllowedTokens.isEmpty { return }
        alwaysAllowedTokens = alwaysAllowedTokens.intersection(managedSet)
    }

    @ViewBuilder
    func selectionSection(title: String,
                          subtitle: String,
                          buttonLabel: String,
                          countLabel: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                Task {
                    let approved = await IntentBlockManager.shared.ensureAuthorization()
                    await MainActor.run {
                        authDenied = !approved
                        if approved {
                            showPicker = true
                        }
                    }
                }
            } label: {
                Text(buttonLabel)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            Text(countLabel)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
        }
    }
}
