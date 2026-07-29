import SwiftUI

struct WebsitePickerView: View {
    @Binding var domains: [String]
    @FocusState.Binding var focusedField: FocusCommandField?
    let onAdvance: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    @State private var input = ""

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
                        onMoveDown()
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        onMoveDown()
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        onMoveUp()
                        return .handled
                    }
                    .onKeyPress(.leftArrow) {
                        onMoveUp()
                        return .handled
                    }

                Button(action: addDomain) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

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
    }

    private func addDomain() {
        guard let normalized = normalizedDomain(input), !domains.contains(normalized) else {
            input = ""
            return
        }
        domains.append(normalized)
        input = ""
    }

    private func handleSubmit() {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onAdvance()
        } else {
            addDomain()
        }
    }

    private func normalizedDomain(_ rawValue: String) -> String? {
        WebsiteAllowlist.normalizedDomain(rawValue)
    }
}
