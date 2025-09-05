import SwiftUI
import SwiftData

struct EditSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: FocusSession

    @State private var localNote: String = ""
    @State private var newTag: String = ""

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

                Section("Note") {
                    TextField("Add a note…", text: $localNote, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section("Tags") {
                    HStack {
                        TextField("Add tag (e.g., thesis)", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") { addTag() }
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(session.tags, id: \.self) { tag in
                                TagChip(title: "#\(tag)") {
                                    removeTag(tag)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
            .onAppear { localNote = session.note ?? "" }
        }
    }

    private func saveAndClose() {
        session.note = localNote.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        dismiss()
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !session.tags.contains(trimmed) {
            session.tags.append(trimmed)
            try? modelContext.save()
        }
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        session.tags.removeAll { $0 == tag }
        try? modelContext.save()
    }
}

#Preview {
    ContentView()
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
