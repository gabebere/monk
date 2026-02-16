import SwiftUI
import SwiftData

struct ProjectGridListView: View {
    @EnvironmentObject private var focus: FocusManager
    @AppStorage("projects.viewMode") private var viewModeRaw: String = ProjectViewMode.grid.rawValue
    @AppStorage("projects.sortMode") private var sortModeRaw: String = ProjectSortMode.recent.rawValue
    @AppStorage("projects.showArchived") private var showArchived: Bool = false
    let embedInScroll: Bool

    let projects: [Project]
    let onSelect: (Project) -> Void
    let onCreate: () -> Void

    private var viewMode: ProjectViewMode { ProjectViewMode(rawValue: viewModeRaw) ?? .grid }
    private var sortMode: ProjectSortMode { ProjectSortMode(rawValue: sortModeRaw) ?? .recent }
    private var scrollTopInset: CGFloat { 24 }
    private var scrollBottomInset: CGFloat { 24 }

    var body: some View {
        Group {
            if embedInScroll {
                if filteredProjects.isEmpty {
                    contentBody
                        .padding(.top, scrollTopInset)
                        .padding(.bottom, scrollBottomInset)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView(showsIndicators: false) {
                        contentBody
                            .padding(.top, scrollTopInset)
                            .padding(.bottom, scrollBottomInset)
                            .padding(.horizontal, 12)
                    }
                    .mask(verticalFadeMask)
                }
            } else {
                contentBody
            }
        }
    }
}

private extension ProjectGridListView {
    var filteredProjects: [Project] {
        projects.filter { showArchived || !$0.isArchived }
    }

    var sortedProjects: [Project] {
        filteredProjects.sorted { lhs, rhs in
            switch sortMode {
            case .recent:
                let leftDate = focus.lastActivityDate(for: lhs) ?? lhs.createdAt
                let rightDate = focus.lastActivityDate(for: rhs) ?? rhs.createdAt
                if leftDate == rightDate { return lhs.createdAt > rhs.createdAt }
                return leftDate > rightDate
            case .name:
                return lhs.title.lowercased() < rhs.title.lowercased()
            }
        }
    }

    var contentBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProjectDisplayToolbar(viewMode: viewMode,
                                  sortMode: sortMode,
                                  showArchived: showArchived,
                                  onSetViewMode: { mode in viewModeRaw = mode.rawValue },
                                  onToggleSort: toggleSortMode,
                                  onToggleArchived: { showArchived.toggle() })

            if filteredProjects.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                Group {
                    switch viewMode {
                    case .grid:
                        gridView
                    case .list:
                        listView
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    var gridView: some View {
        let spacing: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12
        let minimumWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 220 : 150
        let columns = [GridItem(.adaptive(minimum: minimumWidth), spacing: spacing)]
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(sortedProjects) { project in
                let metrics = projectMetrics(for: project)
                ProjectSelectionTile(
                    title: project.title,
                    ratioText: metrics.ratio,
                    detailText: metrics.detail,
                    gradient: ProjectGradientPalette.gradient(at: project.gradientIndex),
                    progressFraction: metrics.fraction,
                    isArchived: project.isArchived
                ) {
                    onSelect(project)
                }
            }
        }
        .padding(.top, 0)
    }

    var listView: some View {
        VStack(spacing: 10) {
            ForEach(sortedProjects) { project in
                let metrics = projectMetrics(for: project)
                ProjectListRow(project: project,
                               ratioText: metrics.ratio,
                               detailText: metrics.detail,
                               progressFraction: metrics.fraction,
                               isArchived: project.isArchived) {
                    onSelect(project)
                }
            }
        }
    }

    var verticalFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    func projectMetrics(for project: Project) -> (ratio: String, detail: String, fraction: Double?) {
        let progress = focus.weeklyGoalProgress(for: project)
        if let goal = progress.goalHours, goal > 0 {
            let ratio = String(format: "%.1fh / %.1fh (%.0f%%)", progress.actualHours, goal, progress.progressFraction * 100)
            let detail = String(format: "Goal %.0fh/week", goal)
            return (ratio, detail, progress.progressFraction)
        } else {
            let totalHours = focus.totalDuration(for: project) / 3600
            return (String(format: "%.1fh", totalHours), "Total focused", nil)
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Text("No projects yet.")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Create one to start tracking your focus.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
            Button {
                Haptics.heavy()
                onCreate()
            } label: {
                Label("New Project", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    func toggleSortMode() {
        sortModeRaw = (sortMode == .recent ? ProjectSortMode.name : .recent).rawValue
    }
}

struct ProjectDisplayToolbar: View {
    let viewMode: ProjectViewMode
    let sortMode: ProjectSortMode
    let showArchived: Bool
    let onSetViewMode: (ProjectViewMode) -> Void
    let onToggleSort: () -> Void
    let onToggleArchived: () -> Void

    var body: some View {
        ViewThatFits {
            HStack(spacing: 8) {
                GlassToolbarButton(systemName: "square.grid.2x2", isSelected: viewMode == .grid) {
                    onSetViewMode(.grid)
                }
                GlassToolbarButton(systemName: "list.bullet", isSelected: viewMode == .list) {
                    onSetViewMode(.list)
                }
                Divider()
                    .frame(height: 22)
                    .background(Color.white.opacity(0.16))
                    .padding(.horizontal, 4)
                GlassToolbarButton(systemName: sortMode == .recent ? "clock.arrow.circlepath" : "textformat.abc", isSelected: true, action: onToggleSort)
                GlassToolbarButton(systemName: showArchived ? "archivebox.fill" : "archivebox", isSelected: showArchived, action: onToggleArchived)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
            )

            compactToolbar
        }
    }
}

private extension ProjectDisplayToolbar {
    var compactToolbar: some View {
        Menu {
            Section("View") {
                Button {
                    onSetViewMode(.grid)
                } label: {
                    Label("Grid", systemImage: "square.grid.2x2")
                        .fontWeight(viewMode == .grid ? .semibold : .regular)
                }
                Button {
                    onSetViewMode(.list)
                } label: {
                    Label("List", systemImage: "list.bullet")
                        .fontWeight(viewMode == .list ? .semibold : .regular)
                }
            }

            Section("Sort") {
                Button {
                    onToggleSort()
                } label: {
                    Label(sortMode == .recent ? "Sort by name" : "Sort by recency",
                          systemImage: "arrow.up.arrow.down")
                }
            }

            Section("Archived") {
                Button {
                    onToggleArchived()
                } label: {
                    Label(showArchived ? "Hide archived" : "Show archived",
                          systemImage: showArchived ? "archivebox.fill" : "archivebox")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .menuStyle(.automatic)
    }
}

struct GlassToolbarButton: View {
    let systemName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.soft()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.24 : 0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

struct ProjectListRow: View {
    let project: Project
    let ratioText: String
    let detailText: String
    let progressFraction: Double?
    let isArchived: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(project.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if isArchived {
                            ArchivedBadge()
                        }
                    }
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))

                    if let fraction = progressFraction {
                        ProgressView(value: fraction, total: 1)
                            .tint(.white)
                    }
                }
                Spacer(minLength: 12)
                Text(ratioText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
            }
            .padding(14)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .opacity(isArchived ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }
}

struct ArchivedBadge: View {
    var body: some View {
        Text("Archived")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.16), in: Capsule())
    }
}
