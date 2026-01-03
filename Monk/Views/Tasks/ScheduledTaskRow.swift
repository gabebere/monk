import SwiftUI

struct ScheduledTaskRow: View {
    @Environment(\.calendar) private var calendar

    let entry: ScheduledTaskEntry
    let isSelected: Bool
    let isDimmed: Bool
    let onEdit: () -> Void
    let onToggleCompletion: () -> Void

    private var titleColor: Color {
        if entry.task.isCompleted {
            return Color.white.opacity(0.65)
        }
        if isDueNow {
            return Color.red.opacity(0.9)
        }
        return .white
    }

    private var projectLabel: String? {
        entry.task.project?.title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: {
                onToggleCompletion()
            }) {
                ZStack {
                    Circle()
                        .stroke(entry.task.isCompleted ? Color.green.opacity(0.9) : Color.white.opacity(0.75), lineWidth: 2)
                        .frame(width: 20 , height: 20)
                    if entry.task.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.green.opacity(0.9))
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.task.displayTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                        .strikethrough(entry.task.isCompleted, color: .white.opacity(0.6))
                }

                if let projectLabel {
                    Text(projectLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

            }

            Spacer()

            Button(action: {
                Haptics.soft()
                onEdit()
            }) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground)
        .overlay(
            selectionStroke
        )
        .opacity(isDimmed ? 0.55 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var isDueNow: Bool {
        let today = calendar.startOfDay(for: Date())
        return entry.day < today
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
    }

    @ViewBuilder
    private var selectionStroke: some View {
        let baseStroke = RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.15), lineWidth: 1)

        if isSelected {
            baseStroke
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                )
                .onAppear { animate = true }
        } else {
            baseStroke
        }
    }

    @State private var animate = false
}
