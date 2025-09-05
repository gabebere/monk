import SwiftUI
import SwiftData
import WidgetKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsList: [Preferences]

    private var prefs: Preferences {
        if let p = prefsList.first { return p }
        let p = Preferences()
        modelContext.insert(p)
        return p
    }

    @State private var exportURL: URL?
    @State private var isSharing: Bool = false
    @State private var showingExportOptions: Bool = false
    @State private var rangeSelection: RangeSelection = .all

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Stepper(value: Binding(
                        get: { prefs.dailyGoalHours },
                        set: { prefs.dailyGoalHours = $0; try? modelContext.save() }
                    ), in: 0...12, step: 0.5) {
                        HStack {
                            Text("Daily goal")
                            Spacer()
                            Text(String(format: "%.1f h", prefs.dailyGoalHours))
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Nudges") {
                    Picker("Cadence", selection: Binding(
                        get: { prefs.nudgeMinutes ?? 0 },
                        set: { prefs.nudgeMinutes = $0 == 0 ? nil : $0; try? modelContext.save() }
                    )) {
                        Text("Off").tag(0)
                        Text("25 minutes").tag(25)
                        Text("50 minutes").tag(50)
                        Text("90 minutes").tag(90)
                    }
                }

                Section("Sync") {
                    Toggle("iCloud sync (optional)", isOn: Binding(
                        get: { prefs.iCloudSyncEnabled },
                        set: { prefs.iCloudSyncEnabled = $0; try? modelContext.save() }
                    ))
                }

                Section("Export") {
                    Button("Export CSV…") { showingExportOptions = true }
                }

                Section("Debug") {
                    Button("Reload Widgets") {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    Button("Write Widget Sample Data") {
                        AppGroupBridge.writeSummary(todayHours: 2.5, last7: [1, 2, 0.5, 3, 2.5, 4, 1.5])
                        WidgetCenter.shared.reloadTimelines(ofKind: "MonkSummaryWidget")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $isSharing) {
                if let exportURL { ActivityView(activityItems: [exportURL]) }
            }
            .sheet(isPresented: $showingExportOptions) {
                NavigationStack {
                    Form {
                        Picker("Range", selection: $rangeSelection) {
                            Text("All time").tag(RangeSelection.all)
                            Text("Last 7 days").tag(RangeSelection.lastDays(7))
                            Text("Last 30 days").tag(RangeSelection.lastDays(30))
                        }
                        .pickerStyle(.inline)
                    }
                    .navigationTitle("Export Options")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingExportOptions = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Export") {
                                showingExportOptions = false
                                exportCSV()
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}

extension SettingsView {
    private func exportCSV() {
        var predicate: Predicate<FocusSession>? = nil
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        switch rangeSelection {
        case .all:
            predicate = nil
        case .lastDays(let n):
            let start = cal.date(byAdding: .day, value: -n, to: now) ?? now
            predicate = #Predicate { $0.startedAt >= start }
        }

        let descriptor: FetchDescriptor<FocusSession>
        if let predicate { descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.startedAt)]) }
        else { descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.startedAt)]) }

        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        let csv = CSVExporter.makeCSV(from: sessions)
        do {
            let url = try CSVExporter.writeTemporaryCSV(csv)
            exportURL = url
            isSharing = true
        } catch {
            // In production, present an error toast
            isSharing = false
        }
    }
}

enum RangeSelection: Hashable {
    case all
    case lastDays(Int)
}
