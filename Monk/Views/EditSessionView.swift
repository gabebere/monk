import SwiftUI
import SwiftData

struct EditSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: FocusSession

    @State private var moodValue: Int = 1

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.08, blue: 0.18),
                        Color(red: 0.03, green: 0.04, blue: 0.11)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Session details")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Text("Review and update how this focus session felt.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        DetailCard(icon: "clock.fill",
                                   title: "Timing",
                                   subtitle: "When this session started and ended.") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Started")
                                                .font(.footnote)
                                                .foregroundStyle(.white.opacity(0.65))
                                            Text(session.startedAt, format: Date.FormatStyle().weekday(.wide).hour().minute())
                                                .font(.headline.weight(.medium))
                                                .foregroundStyle(.white)
                                        }
                                    } icon: {
                                        Image(systemName: "play.fill")
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    Spacer()
                                }

                                if let end = session.endedAt {
                                    HStack {
                                        Label {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Ended")
                                                    .font(.footnote)
                                                    .foregroundStyle(.white.opacity(0.65))
                                                Text(end, format: Date.FormatStyle().weekday(.wide).hour().minute())
                                                    .font(.headline.weight(.medium))
                                                    .foregroundStyle(.white)
                                            }
                                        } icon: {
                                            Image(systemName: "stop.fill")
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                        Spacer()
                                    }
                                } else {
                                    Label("In progress", systemImage: "record.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        DetailCard(icon: "face.smiling.fill",
                                   title: "Mood",
                                   subtitle: "How did this session feel overall?") {
                            MoodSlider(value: $moodValue)
                        }

                        if let project = session.project {
                            DetailCard(icon: "target",
                                       title: "Project",
                                       subtitle: "This session contributed to \(project.title).") {
                                Text(project.title)
                                    .font(.headline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndClose() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.white)
        .onAppear {
            moodValue = session.moodScore ?? 1
        }
    }

    private func saveAndClose() {
        session.moodScore = moodValue
        try? session.modelContext?.save()
        dismiss()
    }
}

#Preview {
    ContentView()
}

private struct DetailCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }
}
