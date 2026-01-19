
import SwiftUI
import SwiftData

struct EditSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: FocusSession

    @State private var selectedProjectID: UUID?
    @State private var startedAt: Date = Date()
    @State private var endedAt: Date?
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]

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
                        header
                        timingCard
                        projectCard
                        deleteCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32) 
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.heavy()
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.success()
                        saveAndClose()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(.white)
        .onAppear {
            selectedProjectID = session.project?.id
            startedAt = session.startedAt
            endedAt = session.endedAt
        }
        // no sheet needed
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session details")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Review and update this focus session.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timingCard: some View {
        DetailCard(icon: "clock.fill",
                   title: "Timing",
                   subtitle: "When this session started and ended.") {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Started",
                           selection: $startedAt,
                           displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .tint(.white)
                .foregroundStyle(.white)

                if let _ = session.endedAt ?? endedAt {
                    DatePicker("Ended",
                               selection: Binding(
                                get: { endedAt ?? startedAt },
                                set: { endedAt = $0 }
                               ),
                               in: startedAt...,
                               displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(.white)
                    .foregroundStyle(.white)
                } else {
                    Label("In progress session can’t be edited", systemImage: "record.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.red.opacity(0.9))
                }
            }
        }
    }

    private var projectCard: some View {
        DetailCard(icon: "target",
                   title: "Project",
                   subtitle: "Choose which project should own this session.") {
            VStack(alignment: .leading, spacing: 16) {
                Menu {
                    Button("None") {
                        Haptics.heavy()
                        selectedProjectID = nil
                    }
                    ForEach(projects) { project in
                        Button(project.title) {
                            Haptics.heavy()
                            selectedProjectID = project.id
                        }
                    }
                } label: {
                    HStack {
                        Text(projectTitle)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .menuStyle(.automatic)

                Text(projectDescription)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var deleteCard: some View {
        DetailCard(icon: "trash",
                   title: "Delete",
                   subtitle: "Remove this session permanently.") {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Text("Delete session")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Delete session?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete session", role: .destructive) {
                    deleteSession()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var currentProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    private var projectTitle: String {
        currentProject?.title ?? "None"
    }

    private var projectDescription: String {
        if let project = currentProject {
            return "Linked to “\(project.title)” for insights."
        }
        return "This session isn’t linked to a project yet."
    }

    private func saveAndClose() {
        guard let finalEnd = endedAt ?? session.endedAt else {
            errorMessage = "End time is required for past sessions."
            return
        }
        guard finalEnd > startedAt else {
            errorMessage = "End time must be after start time."
            return
        }
        errorMessage = nil

        session.startedAt = startedAt
        session.endedAt = finalEnd
        if let id = selectedProjectID,
           let project = projects.first(where: { $0.id == id }) {
            session.project = project
        } else {
            session.project = nil
        }
        if modelContext.saveOrRollback() {
            dismiss()
        }
    }

    private func deleteSession() {
        modelContext.delete(session)
        if modelContext.saveOrRollback() {
            dismiss()
        }
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
