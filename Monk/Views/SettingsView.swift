import SwiftUI
import SwiftData
import FamilyControls

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @Query private var prefsList: [Preferences]

    private var prefs: Preferences {
        if let existing = prefsList.first {
            if existing.weeklyGoalHours < 1 {
                existing.weeklyGoalHours = 40
                try? modelContext.save()
            } else if existing.weeklyGoalHours <= 24 {
                existing.weeklyGoalHours = max(0, existing.weeklyGoalHours * 7)
                try? modelContext.save()
            }
            return existing
        }
        let created = Preferences()
        modelContext.insert(created)
        return created
    }

    @State private var showingSoftBlockPicker = false
    @State private var softBlockSelection = FamilyActivitySelection()
    @State private var screenTimeDenied = false
    @State private var showingGoalPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatingBackground(base: Theme.settingsBackground(), halo: Theme.settingsHaloGradient)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        goalCard
                        sessionsCard
                        softBlockCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 36)
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear(perform: restoreSoftBlockSelection)
        .onChange(of: softBlockSelection) { _, newValue in
            if newValue.applicationTokens.isEmpty &&
                newValue.categoryTokens.isEmpty &&
                newValue.webDomainTokens.isEmpty &&
                !newValue.includeEntireCategory {
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

private extension SettingsView {
    var goalCard: some View {
        SettingsCard(title: "Weekly Goal",
                     subtitle: "Choose how many hours you aim to focus each week.",
                     icon: "flag.fill") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(selectedGoal) hours")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Currently targeted each week")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            showingGoalPicker.toggle()
                        }
                    } label: {
                        Label(showingGoalPicker ? "Hide picker" : "Adjust goal", systemImage: "slider.horizontal.3")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if showingGoalPicker {
                    Divider().overlay(Color.white.opacity(0.18))
                        .transition(.opacity)
                    Picker("Weekly goal", selection: goalBinding) {
                        ForEach(0...80, id: \.self) { value in
                            Text("\(value) h").tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(height: 160)
                    .colorScheme(.dark)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showingGoalPicker)
    }

    var sessionsCard: some View {
        SettingsCard(title: "Sessions",
                     subtitle: "Keep your history clean by tossing ultra-short focus spurts.",
                     icon: "hourglass") {
            Toggle(isOn: discardShortBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discard sessions under 2 minutes")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                    Text("Stops accidental taps from cluttering your insights.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .tint(Color.cyan)
        }
    }

    var softBlockCard: some View {
        SettingsCard(title: "Soft Blocking",
                     subtitle: "Automatically shield distracting apps every time you focus.",
                     icon: "shield.lefthalf.fill") {
            Toggle(isOn: softBlockEnabledBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable soft blocking")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                    Text("Blocks your selected apps when a session starts.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .tint(Color.purple)

            Button {
                showingSoftBlockPicker = true
            } label: {
                Label("Choose apps and sites", systemImage: "square.and.pencil")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(prefs.softBlockEnabled ? 0.18 : 0.08), in: Capsule(style: .continuous))
                    .foregroundStyle(Color.white.opacity(prefs.softBlockEnabled ? 1 : 0.65))
            }
            .buttonStyle(.plain)
            .disabled(!prefs.softBlockEnabled)
            .opacity(prefs.softBlockEnabled ? 1 : 0.6)

            if screenTimeDenied {
                Text("Screen Time permission required. Open Settings → Screen Time to grant access.")
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.top, 6)
            } else if let summary = softBlockSummary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 6)
            }
        }
    }

    var goalBinding: Binding<Int> {
        Binding(
            get: { Int(prefs.weeklyGoalHours.rounded()) },
            set: { newValue in
                prefs.weeklyGoalHours = Double(newValue)
                try? modelContext.save()
            }
        )
    }

    var discardShortBinding: Binding<Bool> {
        Binding(
            get: { prefs.discardShortSessions ?? false },
            set: { newValue in
                prefs.discardShortSessions = newValue
                try? modelContext.save()
                if newValue { focus.purgeShortSessionsIfNeeded() }
            }
        )
    }

    var softBlockEnabledBinding: Binding<Bool> {
        Binding(
            get: { prefs.softBlockEnabled },
            set: { handleSoftBlockToggle(newValue: $0) }
        )
    }

    var selectedGoal: Int { Int(prefs.weeklyGoalHours.rounded()) }

    func restoreSoftBlockSelection() {
        if let restored = SoftBlockManager.shared.decodeSelection(from: prefs.softBlockSelectionData) {
            softBlockSelection = restored
        }
        applySoftBlock()
    }

    func handleSoftBlockToggle(newValue: Bool) {
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
                    showScreenTimeAlert()
                }
            } else {
                prefs.softBlockEnabled = false
                try? modelContext.save()
                applySoftBlock()
            }
        }
    }

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

    var softBlockSummary: String? {
        guard prefs.softBlockEnabled else { return nil }
        guard let selection = SoftBlockManager.shared.decodeSelection(from: prefs.softBlockSelectionData) else {
            return "No apps selected yet."
        }
        if selection.includeEntireCategory {
            return "Blocking all categories" + (selection.applicationTokens.isEmpty ? "" : " (allowing \(selection.applicationTokens.count) apps)")
        }
        var components: [String] = []
        if !selection.applicationTokens.isEmpty {
            components.append("\(selection.applicationTokens.count) app\(selection.applicationTokens.count == 1 ? "" : "s")")
        }
        if !selection.categoryTokens.isEmpty {
            components.append("\(selection.categoryTokens.count) categor\(selection.categoryTokens.count == 1 ? "y" : "ies")")
        }
        if !selection.webDomainTokens.isEmpty {
            components.append("\(selection.webDomainTokens.count) domain\(selection.webDomainTokens.count == 1 ? "" : "s")")
        }
        return components.isEmpty ? "No apps selected yet." : "Blocking \(components.joined(separator: " · "))"
    }
}

#Preview {
    SettingsView()
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer()
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }
}
