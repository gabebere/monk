import SwiftUI

struct ScheduledTaskRow: View {
    @Environment(\.calendar) private var calendar

    let entry: ScheduledTaskEntry
    let isDimmed: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleCompletion: () -> Void

    @State private var isDeleteRevealed = false
    @State private var dragOffset: CGFloat = 0

    private let revealWidth: CGFloat = 96
    private let revealThreshold: CGFloat = 34

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
        ZStack(alignment: .trailing) {
            deleteAction

            rowContent
                .offset(x: currentOffset)
                .simultaneousGesture(swipeGesture)
                .onTapGesture {
                    if isDeleteRevealed {
                        isDeleteRevealed = false
                        dragOffset = 0
                        Haptics.light()
                    } else {
                        onTap()
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .opacity(isDimmed ? 0.55 : 1.0)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: {
                onToggleCompletion()
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(entry.task.isCompleted ? 0.9 : 0.75), lineWidth: 2)
                        .frame(width: 20 , height: 20)
                    if entry.task.isCompleted {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 11, height: 11)
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
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(max(0, 1 - ((-currentOffset) / revealWidth) * 1.2))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var deleteAction: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(role: .destructive) {
                isDeleteRevealed = false
                dragOffset = 0
                Haptics.heavy()
                onDelete()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.70),
                                    Color.red.opacity(0.48)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)

                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                        Text("Delete")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: revealWidth, height: 42)
            }
            .buttonStyle(.plain)
        }
        .offset(x: deleteOffset)
    }

    private var currentOffset: CGFloat {
        let base = isDeleteRevealed ? -revealWidth : 0
        return base + dragOffset
    }

    private var deleteOffset: CGFloat {
        let exposedWidth = max(0, -currentOffset)
        return max(0, revealWidth - exposedWidth)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base = isDeleteRevealed ? -revealWidth : 0
                let proposed = base + value.translation.width
                let clamped = max(-revealWidth, min(0, proposed))
                dragOffset = clamped - base
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    dragOffset = 0
                    return
                }
                let base = isDeleteRevealed ? -revealWidth : 0
                let projected = base + value.predictedEndTranslation.width
                let shouldReveal = projected <= -revealThreshold
                if shouldReveal != isDeleteRevealed {
                    Haptics.light()
                }
                isDeleteRevealed = shouldReveal
                dragOffset = 0
            }
    }

    private var isDueNow: Bool {
        let today = calendar.startOfDay(for: Date())
        return entry.day < today
    }
}
