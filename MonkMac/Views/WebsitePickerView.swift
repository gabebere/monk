import SwiftUI

struct WebsitePickerView: View {
    @Binding var domains: [String]
    @FocusState.Binding var focusedField: FocusCommandField?
    let onAdvance: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    @AppStorage(WebsiteHistorySuggestionService.enabledDefaultsKey)
    private var historySuggestionsEnabled = true
    @StateObject private var history = WebsiteHistorySuggestionService()
    @State private var input = ""
    @State private var highlightedIndex = 0

    private var historyMatches: [WebsiteHistorySuggestion] {
        guard historySuggestionsEnabled else { return [] }
        return history.matches(for: input, excluding: Set(domains))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Allowed websites")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("All other sites will be blocked")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 9) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)

                TextField("netflix.com", text: $input)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .websites)
                    .onSubmit(handleSubmit)
                    .onKeyPress(.downArrow) {
                        if historyMatches.isEmpty {
                            onMoveDown()
                        } else {
                            moveHighlight(by: 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        if historyMatches.isEmpty {
                            onMoveDown()
                        } else {
                            moveHighlight(by: 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if historyMatches.isEmpty {
                            onMoveUp()
                        } else {
                            moveHighlight(by: -1)
                        }
                        return .handled
                    }
                    .onKeyPress(.leftArrow) {
                        if historyMatches.isEmpty {
                            onMoveUp()
                        } else {
                            moveHighlight(by: -1)
                        }
                        return .handled
                    }
                    .onChange(of: input) {
                        highlightedIndex = 0
                    }

                Button(action: addCurrentInput) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            if historySuggestionsEnabled,
               !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                historyResults
            }

            if !domains.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(domains, id: \.self) { domain in
                            SelectionChip(title: domain, systemImage: "globe") {
                                domains.removeAll { $0 == domain }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if historySuggestionsEnabled {
                history.loadIfNeeded()
            }
        }
        .onChange(of: historySuggestionsEnabled) {
            if historySuggestionsEnabled {
                history.reload()
            }
        }
    }

    @ViewBuilder
    private var historyResults: some View {
        if !historyMatches.isEmpty {
            VStack(spacing: 2) {
                ForEach(Array(historyMatches.enumerated()), id: \.element.id) { index, suggestion in
                    Button {
                        add(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .frame(width: 22)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.title.isEmpty ? suggestion.domain : suggestion.title)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 5) {
                                    Text(suggestion.domain)
                                    Text("·")
                                    Text(suggestion.browserName)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Image(systemName: "return")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        index == highlightedIndex ? Color.primary.opacity(0.11) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .onHover { isHovering in
                        if isHovering { highlightedIndex = index }
                    }
                }
            }
            .padding(5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if history.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking browser history…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
        } else if !history.browserHistoryAccessNeeded.isEmpty {
            HStack(spacing: 8) {
                Text("Allow access to \(history.browserHistoryAccessNeeded.joined(separator: " and ")) history for suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Privacy Settings") {
                    history.openFullDiskAccessSettings()
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
    }

    private func addDomain() {
        guard let normalized = normalizedDomain(input), !domains.contains(normalized) else {
            input = ""
            return
        }
        domains.append(normalized)
        input = ""
    }

    private func addCurrentInput() {
        if historyMatches.indices.contains(highlightedIndex) {
            add(historyMatches[highlightedIndex])
        } else {
            addDomain()
        }
    }

    private func add(_ suggestion: WebsiteHistorySuggestion) {
        if !domains.contains(suggestion.domain) {
            domains.append(suggestion.domain)
        }
        input = ""
        highlightedIndex = 0
    }

    private func handleSubmit() {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onAdvance()
        } else {
            addCurrentInput()
        }
    }

    private func moveHighlight(by offset: Int) {
        guard !historyMatches.isEmpty else { return }
        highlightedIndex = (highlightedIndex + offset + historyMatches.count) % historyMatches.count
    }

    private func normalizedDomain(_ rawValue: String) -> String? {
        WebsiteAllowlist.normalizedDomain(rawValue)
    }
}
