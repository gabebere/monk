import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focus: FocusManager
    @Query private var prefsList: [Preferences]
    @Query(sort: [SortDescriptor(\FocusSession.startedAt, order: .forward)]) private var allSessions: [FocusSession]
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)]) private var projects: [Project]

    @State private var calendarOptions: [CalendarDisplayInfo] = []
    @State private var calendarStatusMessage: String?
    @State private var calendarBusy = false

    private var prefs: Preferences {
        if let existing = prefsList.first {
            var didChange = false
            if existing.weeklyGoalHours < 0 {
                existing.weeklyGoalHours = 0
                didChange = true
            }
            if !existing.hasConvertedDailyGoal {
                if existing.weeklyGoalHours > 0 && existing.weeklyGoalHours <= 24 {
                    existing.weeklyGoalHours = existing.weeklyGoalHours * 7
                }
                existing.hasConvertedDailyGoal = true
                didChange = true
            }
            if didChange {
                modelContext.saveOrRollback()
            }
            return existing
        }
        let created = Preferences(hasConvertedDailyGoal: true)
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
                        calendarCard
                        sessionsCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 36)
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            if prefs.calendarIntegrationEnabled {
                await refreshCalendars()
            }
        }
    }
}

private extension SettingsView {
    var goalCard: some View {
        SettingsCard(title: "Project Goals",
                     subtitle: "Weekly targets now come from the sum of all project goals (capped at 112h).",
                     icon: "flag.fill") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%.0fh planned", projectGoalTotal))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Across all projects this week")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("\(String(format: "%.0fh remaining", remainingGoalBudget))", systemImage: "speedometer")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("Cap: 112h/week")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Text("Adjust goals per project from the Home tab. New goals are blocked once the 112h cap is reached.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    var calendarCard: some View {
        SettingsCard(title: "Calendar sync",
                     subtitle: "Automatically log sessions to your personal calendars.",
                     icon: "calendar") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: calendarEnabledBinding) {
                    Text("Create events when sessions end")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .tint(Color.cyan)

                if prefs.calendarIntegrationEnabled {
                    if calendarOptions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if calendarBusy {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("No writable calendars available. Make sure the account is added in Settings › Calendar and allows edits.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    } else {
                        Picker("Calendar", selection: calendarSelection) {
                            ForEach(calendarOptions) { option in
                                Text("\(option.title) — \(option.sourceName)")
                                    .tag(option.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accentColor(.white)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await refreshCalendars() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await syncCalendarHistory() }
                        } label: {
                            HStack {
                                if calendarBusy {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Sync past sessions")
                                    .font(.footnote.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(calendarBusy || (prefs.calendarCalendarIdentifier ?? "").isEmpty)

                        Button(role: .destructive) {
                            Task { await removeAllMonkEvents() }
                        } label: {
                            Text("Delete all [Monk] events")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(calendarBusy)
                    }
                } else {
                    Text("Turn this on to mirror Monk sessions onto one of your existing calendars.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let status = calendarStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
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

    var calendarEnabledBinding: Binding<Bool> {
        Binding(
            get: { prefs.calendarIntegrationEnabled },
            set: { newValue in
                prefs.calendarIntegrationEnabled = newValue
                modelContext.saveOrRollback()
                Task { await handleCalendarToggle(enabled: newValue) }
            }
        )
    }

    var calendarSelection: Binding<String> {
        Binding(
            get: { prefs.calendarCalendarIdentifier ?? "" },
            set: { newValue in
                let normalized = newValue.isEmpty ? nil : newValue
                guard prefs.calendarCalendarIdentifier != normalized else { return }
                let previous = prefs.calendarCalendarIdentifier
                prefs.calendarCalendarIdentifier = normalized
                modelContext.saveOrRollback()
                Task {
                    await handleCalendarSelectionChange(from: previous, to: normalized)
                }
            }
        )
    }

    var rawProjectGoalTotal: Double {
        projects
            .compactMap { $0.weeklyGoalHours }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    var projectGoalTotal: Double { min(rawProjectGoalTotal, 112) }

    var remainingGoalBudget: Double {
        max(0, 112 - rawProjectGoalTotal)
    }

}

private extension SettingsView {
    func handleCalendarToggle(enabled: Bool) async {
        if enabled {
            let granted = await CalendarIntegration.shared.requestAccess()
            guard granted else {
                await MainActor.run {
                    calendarStatusMessage = "Calendar access denied."
                    prefs.calendarIntegrationEnabled = false
                    modelContext.saveOrRollback()
                }
                return
            }
            await refreshCalendars()
            await syncCalendarHistory()
        } else {
            await MainActor.run {
                calendarBusy = false
                calendarOptions = []
                prefs.calendarCalendarIdentifier = nil
                modelContext.saveOrRollback()
                calendarStatusMessage = "Calendar sync disabled."
            }
        }
    }

    func syncCalendarHistory() async {
        guard prefs.calendarIntegrationEnabled else { return }
        await MainActor.run {
            calendarBusy = true
            calendarStatusMessage = "Syncing past sessions…"
        }
        guard let identifier = prefs.calendarCalendarIdentifier, !identifier.isEmpty else {
            await MainActor.run {
                calendarBusy = false
                calendarStatusMessage = "Select a calendar first."
            }
            return
        }
        await CalendarIntegration.shared.backfillSessions(allSessions, calendarIdentifier: identifier)
        await MainActor.run {
            calendarBusy = false
            calendarStatusMessage = "Calendar is up to date."
        }
    }

    func refreshCalendars() async {
        let calendars = await CalendarIntegration.shared.availableCalendars()
        await MainActor.run {
            calendarOptions = calendars
            if prefs.calendarCalendarIdentifier == nil,
               let first = calendars.first {
                prefs.calendarCalendarIdentifier = first.id
                modelContext.saveOrRollback()
            }
        }
        await MainActor.run {
            updateSelectionStatus()
        }
    }

    @MainActor
    func updateSelectionStatus() {
        if let identifier = prefs.calendarCalendarIdentifier,
           let option = calendarOptions.first(where: { $0.id == identifier }) {
            calendarStatusMessage = "Using \(option.title) in \(option.sourceName)."
        } else {
            calendarStatusMessage = "Choose which calendar Monk should write to."
        }
    }

    func handleCalendarSelectionChange(from previous: String?, to newValue: String?) async {
        guard prefs.calendarIntegrationEnabled else { return }
        await MainActor.run {
            calendarBusy = true
            calendarStatusMessage = "Updating calendar selection…"
        }
        var removedCount = 0
        if let previous, !previous.isEmpty {
            removedCount = await CalendarIntegration.shared.purgeMonkEvents(in: previous)
        }
        if let newValue, !newValue.isEmpty {
            await CalendarIntegration.shared.backfillSessions(allSessions, calendarIdentifier: newValue)
        }
        await MainActor.run {
            calendarBusy = false
            updateSelectionStatus()
            if removedCount > 0 {
                calendarStatusMessage = "Moved calendar. Removed \(removedCount) old events."
            } else {
                calendarStatusMessage = "Calendar updated. (Some accounts only allow adding events.)"
            }
        }
    }

    func removeAllMonkEvents() async {
        await MainActor.run {
            calendarBusy = true
            calendarStatusMessage = "Deleting Monk events…"
        }
        let removed = await CalendarIntegration.shared.purgeAllMonkEvents()
        await MainActor.run {
            calendarBusy = false
            if removed > 0 {
                calendarStatusMessage = "Removed \(removed) Monk-tagged events."
            } else {
                calendarStatusMessage = "No removable Monk events found (account may be write-only)."
            }
        }
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
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }
}
