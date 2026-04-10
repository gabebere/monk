import SwiftUI
import SwiftData
import Charts

struct ProjectGridListView: View {
    @EnvironmentObject private var focus: FocusManager
    @AppStorage("projects.viewMode") private var viewModeRaw: String = ProjectViewMode.grid.rawValue
    @AppStorage("projects.sortMode") private var sortModeRaw: String = ProjectSortMode.recent.rawValue
    @AppStorage("projects.showArchived") private var showArchived: Bool = false
    let embedInScroll: Bool
    var showsToolbar: Bool = true
    var contentHorizontalPadding: CGFloat = 12
    var contentTopPadding: CGFloat = 24
    var contentBottomPadding: CGFloat = 24

    let projects: [Project]
    let onFocus: (Project) -> Void
    let onOpenDetails: (Project) -> Void
    let onCreate: () -> Void

    private var viewMode: ProjectViewMode { ProjectViewMode(rawValue: viewModeRaw) ?? .grid }
    private var sortMode: ProjectSortMode { ProjectSortMode(rawValue: sortModeRaw) ?? .recent }
    var body: some View {
        Group {
            if embedInScroll {
                if filteredProjects.isEmpty {
                    contentBody
                        .padding(.top, contentTopPadding)
                        .padding(.bottom, contentBottomPadding)
                        .padding(.horizontal, contentHorizontalPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView(showsIndicators: false) {
                        contentBody
                            .padding(.top, contentTopPadding)
                            .padding(.bottom, contentBottomPadding)
                            .padding(.horizontal, contentHorizontalPadding)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                contentBody
            }
        }
    }
}

private struct ProjectWeeklyPieSlice: Identifiable {
    let id: UUID
    let title: String
    let hours: Double
    let color: Color
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
            if showsToolbar {
                ProjectDisplayToolbar(viewMode: viewMode,
                                      sortMode: sortMode,
                                      showArchived: showArchived,
                                      onSetViewMode: { mode in viewModeRaw = mode.rawValue },
                                      onToggleSort: toggleSortMode,
                                      onToggleArchived: { showArchived.toggle() })
            }

            if filteredProjects.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                weeklyBreakdownCard

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
                    isArchived: project.isArchived,
                    onAccessoryTap: { onOpenDetails(project) }
                ) {
                    onFocus(project)
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
                               isArchived: project.isArchived,
                               onTap: { onFocus(project) },
                               onAccessoryTap: { onOpenDetails(project) })
            }
        }
    }

    var weeklyBreakdownSlices: [ProjectWeeklyPieSlice] {
        projects
            .filter { !$0.isArchived }
            .compactMap { project in
                let hours = focus.weeklyGoalProgress(for: project).actualHours
                guard hours > 0.01 else { return nil }
                return ProjectWeeklyPieSlice(
                    id: project.id,
                    title: project.title,
                    hours: hours,
                    color: chartColor(for: project.gradientIndex)
                )
            }
            .sorted { $0.hours > $1.hours }
    }

    var weeklyBreakdownTotalHours: Double {
        weeklyBreakdownSlices.reduce(0) { $0 + $1.hours }
    }

    @ViewBuilder
    var weeklyBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Week")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 12)

                Text(formatHoursMinutes(weeklyBreakdownTotalHours))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            if weeklyBreakdownSlices.isEmpty {
                Text("No focus time logged this week yet.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Chart(weeklyBreakdownSlices) { slice in
                        SectorMark(
                            angle: .value("Hours", slice.hours),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.2
                        )
                        .cornerRadius(3)
                        .foregroundStyle(slice.color.gradient)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 150, height: 150)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(weeklyBreakdownSlices.prefix(6))) { slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 8, height: 8)

                                Text(slice.title)
                                    .lineLimit(1)
                                    .foregroundStyle(.white.opacity(0.88))

                                Spacer(minLength: 8)

                                Text(formatHoursMinutes(slice.hours))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                            }
                            .font(.caption.weight(.semibold))
                        }

                        if weeklyBreakdownSlices.count > 6 {
                            Text("+\(weeklyBreakdownSlices.count - 6) more projects")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    func chartColor(for gradientIndex: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.37, green: 0.70, blue: 0.99),
            Color(red: 0.22, green: 0.84, blue: 0.78),
            Color(red: 0.53, green: 0.62, blue: 1.00),
            Color(red: 0.29, green: 0.91, blue: 0.54),
            Color(red: 0.99, green: 0.61, blue: 0.42),
            Color(red: 0.99, green: 0.44, blue: 0.56),
            Color(red: 0.95, green: 0.82, blue: 0.39),
            Color(red: 0.72, green: 0.68, blue: 0.99)
        ]
        let index = abs(gradientIndex) % palette.count
        return palette[index]
    }

    func formatHoursMinutes(_ hours: Double) -> String {
        let totalMinutes = max(0, Int((hours * 60).rounded()))
        let hourComponent = totalMinutes / 60
        let minuteComponent = totalMinutes % 60
        if hourComponent == 0 {
            return "\(minuteComponent)m"
        }
        return "\(hourComponent)h" + String(format: "%02dm", minuteComponent)
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
        ContentUnavailableView {
            Label("No projects yet", systemImage: "square.grid.2x2")
                .font(.title3.weight(.semibold))
        } description: {
            Text("Monk works through projects. Add your first project, set a weekly goal, and choose blocked apps.")
                .foregroundStyle(.white.opacity(0.72))
        } actions: {
            Button {
                Haptics.heavy()
                onCreate()
            } label: {
                Label("Add Project", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .tint(Color.white.opacity(0.24))
            .foregroundStyle(.white)
            .guidedTutorialAnchor(.projectsEmptyCreateButton)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .center)
        .guidedTutorialAnchor(.projectsContentArea)
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
    let onAccessoryTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let onAccessoryTap {
                Button {
                    Haptics.soft()
                    onAccessoryTap()
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .opacity(isArchived ? 0.7 : 1)
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
