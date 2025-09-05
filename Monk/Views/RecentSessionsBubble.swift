import SwiftUI
import SwiftData

struct RecentSessionsBubble: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt, order: .reverse)])
    private var sessions: [FocusSession]

    @State private var showingAll: Bool = false

    var body: some View {
        let ended = sessions.filter { $0.endedAt != nil }
        let recent = Array(ended.prefix(8))

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Sessions")
                    .font(.headline)
                Spacer()
            }

            HistogramView(sessions: recent, showLabels: false)
                .frame(maxHeight: .infinity)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .contentShape(Rectangle())
        .frame(height: 150)
        .onTapGesture { showingAll = true }
        .sheet(isPresented: $showingAll) {
            AllSessionsSheet()
        }
    }
}

private struct HistogramView: View {
    let sessions: [FocusSession]
    var showLabels: Bool = false
    var body: some View {
        GeometryReader { geo in
            let maxDur = max(60.0, sessions.map { durationMinutes($0) }.max() ?? 60.0)
            let count = max(1, sessions.count)
            let spacing: CGFloat = 6
            let barW = max(6, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(sessions, id: \.id) { s in
                    let minutes = durationMinutes(s)
                    let h = CGFloat(minutes / maxDur) * geo.size.height
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.9))
                            .frame(width: barW, height: max(4, h))
                        if showLabels {
                            Text(shortTime(s))
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: barW * 1.6)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .accessibilityLabel("Session \(s.startedAt.formatted(date: .omitted, time: .shortened)) lasting \(Int(minutes)) minutes")
                }
            }
        }
    }

    private func durationMinutes(_ s: FocusSession) -> Double {
        let end = s.endedAt ?? Date()
        return max(0, end.timeIntervalSince(s.startedAt) / 60.0)
    }

    private func shortTime(_ s: FocusSession) -> String {
        s.startedAt.formatted(date: .omitted, time: .shortened)
    }
}

private struct AllSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt, order: .reverse)])
    private var sessions: [FocusSession]

    @State private var editing: FocusSession? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { s in
                    Button {
                        editing = s
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.startedAt, format: .dateTime.weekday(.abbreviated).day().month())
                                HStack(spacing: 4) {
                                    Text(s.startedAt, style: .time)
                                    Text("–")
                                    Text((s.endedAt ?? Date()), style: .time)
                                }
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(durationString(s))
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $editing) { session in
                NavigationStack { EditSessionView(session: session) }
            }
        }
    }

    private func durationString(_ s: FocusSession) -> String {
        let end = s.endedAt ?? Date()
        let sec = max(0, end.timeIntervalSince(s.startedAt))
        let h = Int(sec) / 3600
        let m = (Int(sec) % 3600) / 60
        if h >= 1 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%dm", m)
    }
}
