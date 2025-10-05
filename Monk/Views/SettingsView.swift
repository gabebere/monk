import SwiftUI
import SwiftData
import FamilyControls
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @Query private var prefsList: [Preferences]

    private var prefs: Preferences {
        if let p = prefsList.first {
            if p.weeklyGoalHours < 1 {
                p.weeklyGoalHours = 40
                try? modelContext.save()
            } else if p.weeklyGoalHours <= 24 {
                p.weeklyGoalHours = max(0, p.weeklyGoalHours * 7)
                try? modelContext.save()
            }
            return p
        }
        let p = Preferences()
        modelContext.insert(p)
        return p
    }

    @State private var showingSoftBlockPicker: Bool = false
    @State private var softBlockSelection: FamilyActivitySelection = FamilyActivitySelection()
    @State private var screenTimeDenied: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatingBackground(base: Theme.settingsBackground(), halo: Theme.settingsHaloGradient)
                Form {
                    Section("Goal") {
                        NavigationLink {
                            WeeklyGoalPicker(goal: Binding(
                                get: { prefs.weeklyGoalHours },
                                set: { prefs.weeklyGoalHours = $0; try? modelContext.save() }
                            ))
                        } label: {
                            HStack {
                                Text("Weekly goal")
                                Spacer()
                                Text("\(Int(prefs.weeklyGoalHours)) h")
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }

                Section("Sessions") {
                    Toggle("Discard sessions under 2 min", isOn: Binding(
                        get: { prefs.discardShortSessions ?? false },
                        set: { newValue in
                            prefs.discardShortSessions = newValue
                            try? modelContext.save()
                            if newValue { focus.purgeShortSessionsIfNeeded() }
                        }
                    ))
                }

                Section("Soft Block") {
                    Toggle("Enable soft blocking", isOn: Binding(
                        get: { prefs.softBlockEnabled },
                        set: { newValue in
                            Task { @MainActor in
                                if newValue {
                                    let approved = await SoftBlockManager.shared.ensureAuthorization()
                                    if approved {
                                        prefs.softBlockEnabled = true
                                        try? modelContext.save()
                                        applySoftBlock()
                                    } else {
                                        prefs.softBlockEnabled = false
                                        try? modelContext.save()
                                        // Present alert letting user know authorization is required
                                        showScreenTimeAlert()
                                    }
                                } else {
                                    prefs.softBlockEnabled = false
                                    try? modelContext.save()
                                    applySoftBlock()
                                }
                            }
                        }
                    ))

                    Button("Choose apps…") { showingSoftBlockPicker = true }
                        .disabled(!prefs.softBlockEnabled)

                    Text(softBlockSelection.applicationTokens.isEmpty ? "No apps selected" : "\(softBlockSelection.applicationTokens.count) app(s) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if screenTimeDenied {
                        Text("Screen Time permission required. Open Settings → Screen Time to grant access.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .formStyle(.grouped)
        }
        .navigationTitle("Settings")
        .onAppear {
            if let restored = SoftBlockManager.shared.decodeSelection(from: prefs.softBlockSelectionData) {
                softBlockSelection = restored
            }
            applySoftBlock()
        }
        .onChange(of: softBlockSelection) { _, newValue in
            if newValue.applicationTokens.isEmpty {
                prefs.softBlockSelectionData = nil
            } else {
                prefs.softBlockSelectionData = SoftBlockManager.shared.encodeSelection(newValue)
            }
            try? modelContext.save()
            applySoftBlock()
        }
        .familyActivityPicker(isPresented: $showingSoftBlockPicker, selection: $softBlockSelection)
    }
}
}

#Preview {
    SettingsView()
}

private extension SettingsView {
    func applySoftBlock() {
        let hasTokens = softBlockSelection.includeEntireCategory ||
            !(softBlockSelection.applicationTokens.isEmpty &&
              softBlockSelection.categoryTokens.isEmpty &&
              softBlockSelection.webDomainTokens.isEmpty)
        let selection = hasTokens ? softBlockSelection : nil
        SoftBlockManager.shared.apply(selection: selection, enabled: prefs.softBlockEnabled)
    }

    func showScreenTimeAlert() {
        screenTimeDenied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            screenTimeDenied = false
        }
    }
}

private struct WeeklyGoalPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var goal: Double
    @State private var selection: Int

    private let range = Array(stride(from: 0, through: 80, by: 1))

    init(goal: Binding<Double>) {
        _goal = goal
        _selection = State(initialValue: Int(goal.wrappedValue.rounded()))
    }

    var body: some View {
        Form {
            Picker("Hours per week", selection: $selection) {
                ForEach(range, id: \.self) { value in
                    Text("\(value) h").tag(value)
                }
            }
            .pickerStyle(.wheel)
        }
        .navigationTitle("Weekly Goal")
        .onAppear { selection = Int(goal.rounded()) }
        .onChange(of: selection) { _, newValue in
            goal = Double(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
