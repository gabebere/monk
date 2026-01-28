import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt, order: .reverse)])
    private var sessions: [FocusSession]
    @State private var editing: FocusSession? = nil

    var body: some View {
        ZStack {
            AnimatingBackground(base: Theme.historyBackground(), halo: Theme.historyHaloGradient)
            List {
                ForEach(sessions, id: \.persistentModelID) { session in
                    Button {
                        editing = session
                    } label: {
                        HistoryRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.white.opacity(0.08))
                }
                .onDelete(perform: deleteSessions)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("History")
        .sheet(item: $editing) { session in
            NavigationStack { EditSessionView(session: session) }
        }
    }
}

private extension HistoryView {
    func deleteSessions(at offsets: IndexSet) {
        offsets.map { sessions[$0] }.forEach { session in
            modelContext.delete(session)
        }
        modelContext.saveOrRollback()
    }
}

private struct HistoryRow: View {
    let session: FocusSession

    private var titleLine: String {
        if let project = session.project {
            return project.title
        }
        return "No project"
    }

    private var timeLine: String {
        let end = session.endedAt ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let startStr = formatter.string(from: session.startedAt)
        let endStr = formatter.string(from: end)

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "E, d MMM"
        let dayStr = dayFormatter.string(from: session.startedAt)

        return "\(startStr)-\(endStr), \(dayStr)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titleLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(durationString(session))
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }

            Text(timeLine)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let task = session.task {
                Text(task.displayTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func durationString(_ session: FocusSession) -> String {
        let end = session.endedAt ?? Date()
        let seconds = max(0, end.timeIntervalSince(session.startedAt))
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours >= 1 { return String(format: "%dh %02dm", hours, minutes) }
        return String(format: "%dm", minutes)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [FocusSession.self, Project.self, Preferences.self, FocusTask.self, HealthSampleLink.self], inMemory: true)
}
