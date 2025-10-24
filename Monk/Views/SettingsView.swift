import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @Query private var prefsList: [Preferences]

    @State private var showingGoalPicker = false

    private var prefs: Preferences {
        if let existing = prefsList.first {
            if existing.weeklyGoalHours < 1 {
                existing.weeklyGoalHours = 40
                modelContext.saveOrRollback()
            } else if existing.weeklyGoalHours <= 24 {
                existing.weeklyGoalHours = max(0, existing.weeklyGoalHours * 7)
                modelContext.saveOrRollback()
            }
            return existing
        }
        let created = Preferences()
        modelContext.insert(created)
        return created
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatingBackground(base: Theme.settingsBackground(), halo: Theme.settingsHaloGradient)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        goalCard
                        sessionsCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 36)
                }
            }
            .navigationTitle("Settings")
        }
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

    var goalBinding: Binding<Int> {
        Binding(
            get: { Int(prefs.weeklyGoalHours.rounded()) },
            set: { newValue in
                prefs.weeklyGoalHours = Double(newValue)
                modelContext.saveOrRollback()
            }
        )
    }

    var discardShortBinding: Binding<Bool> {
        Binding(
            get: { prefs.discardShortSessions ?? false },
            set: { newValue in
                prefs.discardShortSessions = newValue
                let didSave = modelContext.saveOrRollback()
                if newValue && didSave {
                    focus.purgeShortSessionsIfNeeded()
                }
            }
        )
    }

    var selectedGoal: Int { Int(prefs.weeklyGoalHours.rounded()) }
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
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }
}
