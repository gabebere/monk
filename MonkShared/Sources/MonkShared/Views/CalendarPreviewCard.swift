import SwiftUI

public struct CalendarPreviewCard: View {
    public let session: FocusSession
    public let projectTitle: String?
    public let calendarIdentifier: String?
    public let calendarEnabled: Bool
    public let locationStatus: String?

    public init(session: FocusSession,
                projectTitle: String?,
                calendarIdentifier: String?,
                calendarEnabled: Bool,
                locationStatus: String?) {
        self.session = session
        self.projectTitle = projectTitle
        self.calendarIdentifier = calendarIdentifier
        self.calendarEnabled = calendarEnabled
        self.locationStatus = locationStatus
    }

    private var title: String {
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

    public var body: some View {
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
