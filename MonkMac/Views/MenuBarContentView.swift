import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: FocusSessionStore
    let showCommandPanel: () -> Void

    var body: some View {
        if let policy = store.activePolicy {
            Text(policy.intention)
                .font(.headline)
            Text(store.remainingTimeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Divider()
            Button("Show Focus", action: showCommandPanel)
                .keyboardShortcut(" ", modifiers: .option)

            Divider()
            SettingsLink()
        } else {
            if store.defaultBlockingEnabled {
                Label("Default blocking on", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                Divider()
            }
            Button("Begin Focus", action: showCommandPanel)
                .keyboardShortcut(" ", modifiers: .option)

            Divider()
            SettingsLink()
            if !store.defaultBlockingEnabled {
                Button("Quit MonkOS") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
