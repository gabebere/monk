import SwiftUI

struct CalendarPreviewCard: View {
    let session: FocusSession
    let projectTitle: String?
    let calendarIdentifier: String?
    let calendarEnabled: Bool
    let locationStatus: String?

    private var title: String {
        let taskName = session.task?.displayTitle ?? session.task?.title
        if let taskName,
           let projectTitle,
           !projectTitle.isEmpty {
            return "\(taskName) from \(projectTitle)"
        }
        if let taskName {
            return taskName
        }
        if let projectTitle, !projectTitle.isEmpty {
            return projectTitle
        }
        return "Focus Session"
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let start = formatter.string(from: session.startedAt)
        let end = formatter.string(from: session.endedAt ?? Date())
        return "\(start) – \(end)"
    }

    private var calendarLine: String {
        guard calendarEnabled else { return "Calendar sync is off" }
        if let id = calendarIdentifier, !id.isEmpty {
            return "Will sync to \(id)"
        }
        return "Calendar sync enabled"
    }

    private var locationLine: String {
        if let location = session.locationName, !location.isEmpty {
            return location
        }
        return locationStatus ?? "Location pending..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Calendar preview", systemImage: "calendar")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeRange)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                Text(locationLine)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                Text(calendarLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
