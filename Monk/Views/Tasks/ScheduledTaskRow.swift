import SwiftUI

struct ScheduledTaskRow: View {
    let entry: ScheduledTaskEntry
    let onStart: () -> Void
    let onToggleCompletion: () -> Void

    private var titleColor: Color {
        if entry.task.isCompleted {
            return Color.white.opacity(0.65)
        }
        return .white
    }

    private var projectLabel: String? {
        entry.task.project?.title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggleCompletion) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(entry.task.isCompleted ? 0.9 : 0.75), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if entry.task.isCompleted {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 11, height: 11)
                    }
                }
                .animation(nil, value: entry.task.isCompleted)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .buttonStyle(.plain)

            Button(action: onStart) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.task.displayTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(titleColor)
                            .lineLimit(2)
                            .strikethrough(entry.task.isCompleted, color: .white.opacity(0.6))

                        if let projectLabel {
                            Text(projectLabel)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                        }

                        if !entry.task.isCompleted && entry.task.project == nil {
                            Text("Pick project on first focus")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
