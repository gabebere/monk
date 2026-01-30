import SwiftUI
import SwiftData
import FamilyControls
import ManagedSettings
import UIKit
import OSLog

struct IntentSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager

    let dismiss: () -> Void
    let onSaved: (() -> Void)?

    @State private var alwaysAllowed = FamilyActivitySelection()
    @State private var unlockableApps = FamilyActivitySelection()
    @State private var neverBlockCategories = FamilyActivitySelection()
    @State private var isSaving = false
    @State private var showPicker = false
    @State private var pickerMode: PickerMode = .alwaysAllowed
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
                selectionSection(title: "Always allowed apps",
                                 subtitle: "These stay accessible even when Intent Mode blocks everything else.",
                                 buttonLabel: "Select Apps",
                                 countLabel: selectedCountLabel(alwaysAllowed),
                                 mode: .alwaysAllowed)

                selectionSection(title: "Unlockable apps",
                                 subtitle: "Apps you can unlock via typing and Shortcut/Siri.",
                                 buttonLabel: "Select Unlockable Apps",
                                 countLabel: selectedCountLabel(unlockableApps),
                                 mode: .unlockable)

                selectionSection(title: "Never block categories",
                                 subtitle: "These categories stay accessible while Intent Mode is on.",
                                 buttonLabel: "Select Categories",
                                 countLabel: categoryCountLabel(neverBlockCategories),
                                 mode: .neverBlock)

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
            .familyActivityPicker(isPresented: $showPicker, selection: pickerBinding)
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
        alwaysAllowed = decodeSelection(from: prefs.baselineAlwaysAllowedSelectionData) ?? FamilyActivitySelection()
        unlockableApps = decodeSelection(from: prefs.baselineUnlockableAppsSelectionData) ?? FamilyActivitySelection()
        neverBlockCategories = decodeSelection(from: prefs.baselineNeverBlockCategoriesSelectionData) ?? FamilyActivitySelection()
    }

    func saveSelections() async {
        await MainActor.run { isSaving = true }
        prefs.baselineAlwaysAllowedSelectionData = encodeSelection(alwaysAllowed)
        prefs.baselineUnlockableAppsSelectionData = encodeSelection(unlockableApps)
        // Persist only category tokens for never block; zero apps to avoid unintended allowlist.
        var categoriesOnly = FamilyActivitySelection()
        categoriesOnly.categoryTokens = neverBlockCategories.categoryTokens
        prefs.baselineNeverBlockCategoriesSelectionData = encodeSelection(categoriesOnly)
        modelContext.saveOrRollback()
        IntentAppIndexStore.rebuild(from: prefs.baselineUnlockableAppsSelectionData)

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

    func categoryCountLabel(_ selection: FamilyActivitySelection) -> String {
        let count = selection.categoryTokens.count
        return count == 0 ? "No categories selected" : "\(count) categor\(count == 1 ? "y" : "ies") selected"
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

    var pickerBinding: Binding<FamilyActivitySelection> {
        switch pickerMode {
        case .alwaysAllowed:
            return $alwaysAllowed
        case .unlockable:
            return $unlockableApps
        case .neverBlock:
            return $neverBlockCategories
        }
    }

    @ViewBuilder
    func selectionSection(title: String,
                          subtitle: String,
                          buttonLabel: String,
                          countLabel: String,
                          mode: PickerMode) -> some View {
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
                            pickerMode = mode
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

private enum PickerMode {
    case alwaysAllowed
    case unlockable
    case neverBlock
}
