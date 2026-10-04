import SwiftUI

struct MonkMacSettingsView: View {
    @ObservedObject var store: FocusSessionStore
    @ObservedObject var catalog: ApplicationCatalog
    @ObservedObject var calendarRecorder: CalendarFocusRecorder

    @State private var defaultBlockingEnabled = false
    @State private var alwaysAllowedApplications: [ApplicationDescriptor] = []
    @AppStorage(WebsiteHistorySuggestionService.enabledDefaultsKey)
    private var historySuggestionsEnabled = true
    @FocusState private var focusedField: FocusCommandField?

    var body: some View {
        Form {
            Section("Default access") {
                Toggle("Block apps by default", isOn: $defaultBlockingEnabled)

                Text("When enabled, every app outside this list stays blocked between focus sessions. A timed focus temporarily adds the apps chosen for that task.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ApplicationPickerView(
                    catalog: catalog,
                    selectedApplications: $alwaysAllowedApplications,
                    focusedField: $focusedField,
                    onAdvance: { focusedField = nil },
                    onMoveUp: {},
                    onMoveDown: {},
                    title: "Always allowed",
                    placeholder: "Type an application"
                )

                if catalog.mobileApplications.isEmpty {
                    Text("Open Monk once on your iPhone or iPad to make apps from that device searchable here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if alwaysAllowedApplications.isEmpty && defaultBlockingEnabled {
                    Label("Every app except MonkOS, Finder, and System Settings will be blocked.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(store.activePolicy != nil)

            Section("Website suggestions") {
                Toggle("Suggest domains from browser history", isOn: $historySuggestionsEnabled)
                Text("MonkOS reads recent website titles and domains locally. Browser history is never saved by MonkOS or synced to another device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calendar") {
                Toggle("Add completed focuses to Calendar", isOn: calendarRecordingBinding)
                Text(calendarRecorder.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if calendarRecorder.canOpenPrivacySettings {
                    Button("Open Calendar Privacy Settings") {
                        calendarRecorder.openPrivacySettings()
                    }
                }
            }

            Section {
                HStack {
                    if store.activePolicy != nil {
                        Text("Default access cannot change during an active focus.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Apply") {
                        store.configureDefaultBlocking(
                            enabled: defaultBlockingEnabled,
                            alwaysAllowedApplications: alwaysAllowedApplications
                        )
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.activePolicy != nil || !hasChanges)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .onAppear {
            defaultBlockingEnabled = store.defaultBlockingEnabled
            alwaysAllowedApplications = store.alwaysAllowedApplications
            if catalog.applications.isEmpty {
                catalog.reload()
            }
        }
    }

    private var hasChanges: Bool {
        defaultBlockingEnabled != store.defaultBlockingEnabled ||
            alwaysAllowedApplications != store.alwaysAllowedApplications
    }

    private var calendarRecordingBinding: Binding<Bool> {
        Binding(
            get: { calendarRecorder.isEnabled },
            set: { enabled in
                Task {
                    await calendarRecorder.setEnabled(enabled)
                }
            }
        )
    }
}
