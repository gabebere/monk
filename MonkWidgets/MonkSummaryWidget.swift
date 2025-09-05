import SwiftUI
import WidgetKit

struct SummaryEntry: TimelineEntry { let date: Date; let todayHours: Double; let last7: [Double] }

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { .init(date: .now, todayHours: 2.3, last7: [1,2,0.5,3,2.5,4,1.5]) }
    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(readEntry() ?? placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let entry = readEntry() ?? placeholder(in: context)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 5))))
    }

    private func readEntry() -> SummaryEntry? {
        // NOTE: Include Monk/Shared/AppGroup.swift in the widget target
        // so this matches the main app's App Group ID.
        let suite = UserDefaults(suiteName: AppGroup.id)
        guard let dict = suite?.dictionary(forKey: "summary") else { return nil }
        let today = dict["todayHours"] as? Double ?? 0
        let last7 = dict["last7"] as? [Double] ?? []
        let ts = dict["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        return SummaryEntry(date: Date(timeIntervalSince1970: ts), todayHours: today, last7: last7)
    }
}

struct MonkSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MonkSummaryWidget", provider: SummaryProvider()) { entry in
            MonkSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Deep Work Summary")
        .description("Shows today and 7-day trend.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MonkSummaryWidgetView: View {
    let entry: SummaryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f h", entry.todayHours))
                .font(.system(.title2, design: .monospaced))
                .bold()
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(entry.last7.indices, id: \.self) { i in
                    Capsule()
                        .fill(.tint)
                        .frame(width: 6, height: max(4, CGFloat(entry.last7[i] / max(0.1, entry.last7.max() ?? 1)) * 28))
                }
            }
        }
        .padding()
    }
}

#Preview(as: .systemSmall) {
    MonkSummaryWidget()
} timeline: {
    SummaryEntry(date: .now, todayHours: 2.5, last7: [1,2,0.5,3,2.5,4,1.5])
}
