import SwiftUI
import SwiftData

struct EditSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: FocusSession

    @State private var selectedFeelings: Set<String> = []
    @State private var newTag: String = ""
    @State private var allTags: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    HStack {
                        Text("Started")
                        Spacer()
                        Text(session.startedAt, style: .date)
                        Text(session.startedAt, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    if let end = session.endedAt {
                        HStack {
                            Text("Ended")
                            Spacer()
                            Text(end, style: .date)
                            Text(end, style: .time)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("In progress", systemImage: "record.circle")
                            .foregroundStyle(.orange)
                    }
                }

                Section("What did you do?") {
                    HStack(alignment: .firstTextBaseline) {
                        ZStack(alignment: .leading) {
                            TextField("Add tag (e.g., thesis)", text: $newTag)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit { addFromSubmit() }
                            if let suffix = autocompleteSuffix, !suffix.isEmpty {
                                HStack(spacing: 0) {
                                    Text(newTag).opacity(0)
                                    Text(suffix).foregroundStyle(.secondary)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        Button("Add") { addTag() }
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !matchingSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(matchingSuggestions, id: \.self) { suggestion in
                                    Button(action: { newTag = suggestion }) {
                                        Text("#\(suggestion)")
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundStyle(Color.accentColor)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Use tag \(suggestion)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(session.tags, id: \.self) { tag in
                                TagChip(title: "#\(tag)") { removeTag(tag) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("How do you feel?") {
                    FeelingsMultiSelectView(selected: $selectedFeelings)
                }

                
            }
            .navigationTitle("Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndClose() }
                }
            }
            .onAppear {
                selectedFeelings = Set(session.feelings)
                loadAllTags()
            }
        }
    }

    private func saveAndClose() {
        session.feelings = Array(selectedFeelings).sorted()
        try? modelContext.save()
        dismiss()
    }

    private func addTag() {
        let norm = normalizeTag(newTag)
        guard !norm.isEmpty else { return }
        if !session.tags.contains(where: { normalizeTag($0) == norm }) {
            session.tags.append(norm)
            try? modelContext.save()
        }
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        let norm = normalizeTag(tag)
        session.tags.removeAll { normalizeTag($0) == norm }
        try? modelContext.save()
    }

    // MARK: - Suggestions
    private var matchingSuggestions: [String] {
        let prefix = normalizeTag(newTag)
        guard !prefix.isEmpty else { return [] }
        let existing = Set(session.tags.map { normalizeTag($0) })
        return allTags
            .filter { $0.hasPrefix(prefix) && !existing.contains($0) }
            .sorted()
            .prefix(8)
            .map { $0 }
    }
    private func loadAllTags() {
        let all = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        let set = Set(all.flatMap { $0.tags.map(normalizeTag) })
        allTags = Array(set).sorted()
    }
    private var autocompleteSuffix: String? {
        let prefix = normalizeTag(newTag)
        guard !prefix.isEmpty, let suggestion = matchingSuggestions.first else { return nil }
        guard suggestion.hasPrefix(prefix) else { return nil }
        let dropCount = prefix.count
        if suggestion.count > dropCount { return String(suggestion.dropFirst(dropCount)) }
        return nil
    }
    private func addFromSubmit() {
        if let first = matchingSuggestions.first {
            newTag = first
        }
        addTag()
    }
    private func normalizeTag(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

#Preview {
    ContentView()
}

struct FeelingsMultiSelectView: View {
    @Binding var selected: Set<String>
    private let options = FeelingsCatalog.all
    var body: some View {
        VStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                Button {
                    if selected.contains(opt.id) { selected.remove(opt.id) } else { selected.insert(opt.id) }
                } label: {
                    HStack(spacing: 12) {
                        Text(opt.emoji)
                            .frame(width: 24, alignment: .leading)
                        Text(opt.title)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                        // Reserve space to avoid row height/width shift when selecting
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .opacity(selected.contains(opt.id) ? 1 : 0)
                            .frame(width: 18)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .overlay(
                    Group {
                        if i < options.count - 1 { Divider() }
                    }, alignment: .bottom
                )
            }
        }
    }
}

private struct TagChip: View {
    let title: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "xmark.circle.fill")
                .onTapGesture { onRemove() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
    }
}
