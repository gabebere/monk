import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt, order: .reverse)])
    private var sessions: [FocusSession]
    @State private var editing: FocusSession? = nil

    var body: some View {
        ZStack {
            AnimatingBackground(base: Theme.historyBackground(), halo: Theme.historyHaloGradient)
            List {
                ForEach(sessions) { session in
                    Button {
                        editing = session
                    } label: {
                        HistoryRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.white.opacity(0.08))
                }
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

private struct HistoryRow: View {
    let session: FocusSession

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startedAt, format: .dateTime.weekday(.abbreviated).day().month())
                HStack(spacing: 4) {
                    Text(session.startedAt, style: .time)
                    Text("–")
                    Text((session.endedAt ?? Date()), style: .time)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(durationString(session))
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
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
        .modelContainer(for: FocusSession.self, inMemory: true)
}
