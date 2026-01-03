import SwiftUI
import SwiftData

struct ProjectsTabView: View {
    @State private var showingNewProject: Bool = false
    @State private var projectDetail: Project?
    @EnvironmentObject private var focus: FocusManager
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]

    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)] }

    private var sortedProjects: [Project] {
        projects.sorted { lhs, rhs in
            let leftDate = focus.lastActivityDate(for: lhs) ?? lhs.createdAt
            let rightDate = focus.lastActivityDate(for: rhs) ?? rhs.createdAt
            if leftDate == rightDate { return lhs.createdAt > rhs.createdAt }
            return leftDate > rightDate
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AnimatingBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if sortedProjects.isEmpty {
                        EmptyProjectsView()
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(sortedProjects) { project in
                                let gradient = ProjectGradientPalette.gradient(at: project.gradientIndex)
                                let info = projectProgress(for: project)
                                ProjectSelectionTile(
                                    title: project.title,
                                    ratioText: info.ratio,
                                    detailText: projectDetail(for: project),
                                    gradient: gradient,
                                    progressFraction: info.fraction
                                ) {
                                    projectDetail = project
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Haptics.heavy()
                    showingNewProject = true
                }) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectView()
        }
        .sheet(item: $projectDetail) { project in
            ProjectDetailView(project: project)
        }
    }
}

private extension ProjectsTabView {
    private func projectProgress(for project: Project) -> (ratio: String, fraction: Double?) {
        let progress = focus.weeklyGoalProgress(for: project)
        if let goal = progress.goalHours, goal > 0 {
            return (String(format: "%.1fh / %.1fh", progress.actualHours, goal), progress.progressFraction)
        } else {
            return (String(format: "%.1fh focused", progress.actualHours), nil)
        }
    }

    private func projectDetail(for project: Project) -> String {
        if let goal = project.weeklyGoalHours, goal > 0 {
            return String(format: "Goal %.0fh/week", goal)
        }
        let hours = focus.totalDuration(for: project) / 3600
        return String(format: "%.1fh logged total", hours)
    }
}
