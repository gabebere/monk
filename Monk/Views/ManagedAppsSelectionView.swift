import SwiftUI
import FamilyControls
import ManagedSettings

struct ManagedAppsSelectionView: View {
    let title: String
    let subtitle: String
    let availableTokens: Set<ManagedSettings.ApplicationToken>
    @Binding var selectedTokens: Set<ManagedSettings.ApplicationToken>
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var searchText: String = ""

    private var items: [ManagedAppItem] {
        let indexEntries = IntentAppIndexStore.load()
        var nameByTokenData: [Data: String] = [:]
        for entry in indexEntries {
            nameByTokenData[entry.applicationTokenData] = entry.displayName
        }

        let mapped = availableTokens.map { token -> ManagedAppItem in
            let data = ManagedAppTokenCodec.encodeToken(token)
            let fallbackName = ManagedSettings.Application(token: token).localizedDisplayName ?? "Unknown App"
            let name = data.flatMap { nameByTokenData[$0] } ?? fallbackName
            return ManagedAppItem(token: token,
                                  displayName: name,
                                  identifier: ManagedAppTokenCodec.tokenIdentifier(token))
        }
        let filtered = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? mapped
        : mapped.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                if availableTokens.isEmpty {
                    Text("No managed apps yet. Select managed apps first.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            let indices = Array(items.indices)
                            ForEach(indices, id: \.self) { index in
                                let item = items[index]
                                Button {
                                    toggle(item.token)
                                } label: {
                                    HStack {
                                        Text(item.displayName)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if selectedTokens.contains(item.token) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.tint)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle(title)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                        .disabled(availableTokens.isEmpty)
                }
            }
        }
    }

    private func toggle(_ token: ManagedSettings.ApplicationToken) {
        if selectedTokens.contains(token) {
            selectedTokens.remove(token)
        } else {
            selectedTokens.insert(token)
        }
    }
}

private struct ManagedAppItem: Identifiable {
    let token: ManagedSettings.ApplicationToken
    let displayName: String
    let identifier: String

    var id: String { identifier }
}
