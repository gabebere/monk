import SwiftUI
import SwiftData

struct ProjectsTabView: View {
    @State private var showingNewProject: Bool = false
    @State private var projectDetail: Project?
    @EnvironmentObject private var focus: FocusManager
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]

    var body: some View {
        ZStack(alignment: .top) {
            AnimatingBackground()
            ProjectGridListView(
                embedInScroll: true,
                projects: projects,
                onFocus: { project in
                    guard focus.currentSession == nil else { return }
                    focus.start(project: project, task: nil)
                },
                onOpenDetails: { projectDetail = $0 },
                onCreate: { showingNewProject = true }
            )
        }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
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
                .guidedTutorialAnchor(.projectsAddButton)
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
