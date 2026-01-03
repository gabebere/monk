import Foundation

extension FocusSession {
    var calendarDisplayTitle: String {
        let taskTitle = task?.displayTitle ?? task?.title
        let projectTitle = project?.title ?? task?.project?.title

        if let taskTitle, let projectTitle, !projectTitle.isEmpty {
            return "\(taskTitle) from \(projectTitle)"
        }
        if let taskTitle {
            return taskTitle
        }
        if let projectTitle, !projectTitle.isEmpty {
            return projectTitle
        }
        return "Focus Session"
    }

    var calendarSessionMarker: String {
        "MonkSession:\(id.uuidString)"
    }
}
