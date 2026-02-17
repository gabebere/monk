import SwiftUI
import SwiftData

struct InsightsHomeView: View {
    @EnvironmentObject private var focus: FocusManager
    @Query(sort: [SortDescriptor<FocusSession>(\.startedAt, order: .reverse)]) private var sessions: [FocusSession]
    @Query(sort: [SortDescriptor<FocusTask>(\.updatedAt, order: .reverse)]) private var tasks: [FocusTask]
    @Query(sort: [SortDescriptor<Project>(\.createdAt, order: .forward)]) private var projects: [Project]

    @State private var showingBestWindowSheet = false
    @State private var bestWindowSheetText = ""

    private let service = InsightsService()

    var body: some View {
        ZStack {
            AnimatingBackground(base: Theme.dataBackground(), halo: Theme.dataHaloGradient)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let dashboard = service.makeDashboard(
                    sessions: sessions,
                    tasks: tasks,
                    projects: projects,
                    now: context.date
                )

                ScrollView {
                    VStack(spacing: 16) {
                        MinimalFocusHeroView(
                            model: dashboard.hero,
                            onCalmLaneTap: dashboard.hero.calmLaneText == nil ? nil : {
                                bestWindowSheetText = dashboard.hero.calmLaneText ?? ""
                                showingBestWindowSheet = true
                            }
                        )

                        InsightTextCardView(model: dashboard.bestWindow)
                        TodayRhythmStripView(model: dashboard.rhythm)
                        InsightTextCardView(model: dashboard.momentum)
                        InsightTextCardView(model: dashboard.followThrough)
                        BottomInsightCardView(model: dashboard.bottom)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 52)
                }
            }
        }
        .navigationTitle("Insights")
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .onAppear {
            Analytics.track("insights_viewed", ["screen": "insights_home"])
        }
        .sheet(isPresented: $showingBestWindowSheet) {
            bestWindowSheet
        }
    }

    private var bestWindowSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(bestWindowSheetText)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("This has been your steadiest focus window lately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: startSessionFromBestWindow) {
                    Text("Start a session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(focus.currentSession != nil)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Best focus window")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(260)])
    }

    private func startSessionFromBestWindow() {
        let defaultProject = sessions.first(where: { $0.project != nil })?.project
        if focus.currentSession == nil {
            focus.start(project: defaultProject, task: nil)
        }
        showingBestWindowSheet = false
    }
}
