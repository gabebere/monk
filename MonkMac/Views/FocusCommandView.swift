import SwiftUI

enum FocusCommandField: Hashable {
    case intention
    case hours
    case minutes
    case applications
    case websites

    static let navigationOrder: [FocusCommandField] = [
        .intention,
        .hours,
        .minutes,
        .applications,
        .websites
    ]
}

struct FocusCommandView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: FocusSessionStore
    @ObservedObject var catalog: ApplicationCatalog
    let onDismiss: () -> Void

    @State private var intention = ""
    @State private var hours = ""
    @State private var minutes = ""
    @State private var selectedApplications: [ApplicationDescriptor] = []
    @State private var allowedDomains: [String] = []
    @FocusState private var focusedField: FocusCommandField?

    private var panelSize: CGSize {
        store.activePolicy == nil
            ? CommandPanelMetrics.composerSize
            : CommandPanelMetrics.activeFocusSize
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(0.24)

            if store.activePolicy == nil {
                composer
            } else {
                ActiveFocusView(store: store, onDismiss: onDismiss)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.primary.opacity(0.18), lineWidth: 1)
        }
        .onAppear {
            focusedField = .intention
            if catalog.applications.isEmpty {
                catalog.reload()
            }
        }
        .onExitCommand(perform: onDismiss)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("Monk", systemImage: "circle.hexagongrid.fill")
                    .font(.headline)
                    .foregroundStyle(.primary.opacity(0.82))
                Spacer()
                Text("Esc to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("What are you doing now?", text: $intention)
                .textFieldStyle(.plain)
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .focused($focusedField, equals: .intention)
                .onSubmit {
                    focusedField = .hours
                }
                .onKeyPress(.downArrow) {
                    moveFocus(by: 1)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    moveFocus(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveFocus(by: -1)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    moveFocus(by: -1)
                    return .handled
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("For")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    durationField(
                        suffix: "h",
                        text: hoursText,
                        field: .hours,
                        onSubmit: { focusedField = .minutes }
                    )

                    durationField(
                        suffix: "m",
                        text: minutesText,
                        field: .minutes,
                        onSubmit: { focusedField = .applications }
                    )
                }
            }

            ApplicationPickerView(
                catalog: catalog,
                selectedApplications: $selectedApplications,
                focusedField: $focusedField,
                onAdvance: { focusedField = .websites },
                onMoveUp: { moveFocus(by: -1) },
                onMoveDown: { moveFocus(by: 1) }
            )

            WebsitePickerView(
                domains: $allowedDomains,
                focusedField: $focusedField,
                onAdvance: beginFocus,
                onMoveUp: { moveFocus(by: -1) },
                onMoveDown: { moveFocus(by: 1) }
            )

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.secondary)
                Text("Blocked apps will close immediately. This focus cannot be ended early.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button(action: beginFocus) {
                HStack {
                    Text("Begin focus")
                    Spacer()
                    Text("↩")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(MonkMacTheme.action, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canBegin)
            .opacity(canBegin ? 1 : 0.42)
        }
        .padding(28)
    }

    private var hoursText: Binding<String> {
        Binding(
            get: { hours },
            set: { hours = FocusDurationComponents.sanitizedHours($0) }
        )
    }

    private var minutesText: Binding<String> {
        Binding(
            get: { minutes },
            set: { minutes = FocusDurationComponents.sanitizedMinutes($0) }
        )
    }

    private var durationMinutes: Int {
        FocusDurationComponents.totalMinutes(hours: hours, minutes: minutes)
    }

    private var canBegin: Bool {
        !intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (!selectedApplications.isEmpty || canUseAnInstalledBrowser) &&
            durationMinutes > 0
    }

    private var canUseAnInstalledBrowser: Bool {
        !allowedDomains.isEmpty && !catalog.supportedBrowsers.isEmpty
    }

    private func beginFocus() {
        guard canBegin else { return }
        store.start(
            intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: TimeInterval(durationMinutes * 60),
            allowedApplications: selectedApplications,
            allowedDomains: allowedDomains
        )
    }

    private func durationField(
        suffix: String,
        text: Binding<String>,
        field: FocusCommandField,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 2) {
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: durationDigitWidth(for: text.wrappedValue))
                .focused($focusedField, equals: field)
                .onSubmit(onSubmit)
                .onKeyPress(.downArrow) {
                    moveFocus(by: 1)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    moveFocus(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveFocus(by: -1)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    moveFocus(by: -1)
                    return .handled
                }
            Text(suffix)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .fixedSize(horizontal: true, vertical: false)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    focusedField == field ? Color.primary.opacity(0.46) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
    }

    private func durationDigitWidth(for value: String) -> CGFloat {
        CGFloat(max(value.count, 1) * 9 + 2)
    }

    private func moveFocus(by offset: Int) {
        let order = FocusCommandField.navigationOrder
        guard let focusedField, let index = order.firstIndex(of: focusedField) else {
            self.focusedField = .intention
            return
        }
        let destination = min(max(index + offset, order.startIndex), order.index(before: order.endIndex))
        self.focusedField = order[destination]
    }
}
