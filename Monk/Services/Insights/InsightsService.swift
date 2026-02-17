import Foundation

struct InsightsService {
    private let calendar: Calendar
    private let analyzer: InsightsAnalyzer

    init(calendar: Calendar = Calendar(identifier: .gregorian),
         analyzer: InsightsAnalyzer = InsightsAnalyzer()) {
        self.calendar = calendar
        self.analyzer = analyzer
    }

    func makeDashboard(
        sessions: [FocusSession],
        tasks: [FocusTask],
        projects: [Project],
        now: Date = .now
    ) -> InsightsDashboardModel {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now

        let focusedTodaySeconds = sumOverlappingSeconds(
            sessions: sessions,
            rangeStart: todayStart,
            rangeEnd: tomorrowStart,
            now: now
        )
        let totalWithMonkSeconds = sumAllSessionSeconds(sessions: sessions, now: now)

        let pastWindowSummary = summaryForPast14DaysExcludingToday(sessions: sessions, todayStart: todayStart)
        let calmLaneWindow = calmLaneWindowIfEligible(summary: pastWindowSummary)

        let hero = HeroModel(
            focusedTodayText: formatFocusedToday(seconds: focusedTodaySeconds),
            totalWithMonkText: formatHours(totalWithMonkSeconds),
            calmLaneText: calmLaneWindow.map { "Best focus window: \(hourLaneLabel(start: $0.startHour, end: $0.endHour))" },
            calmLaneWindow: calmLaneWindow
        )

        let bestWindow = makeBestWindowCard(summary: pastWindowSummary)

        let rhythmSummary = analyzer.summarize(
            sessions: sessions,
            now: now,
            config: TemporalInsightsConfig(lookbackDays: 1, bestWindowWidthHours: 2)
        )
        let rhythmMinutes = hourlyMinutes(from: rhythmSummary.hourlyMetrics)
        let rhythm = TodayRhythmModel(
            title: "Today's rhythm",
            hourlyMinutes: rhythmMinutes,
            headline: rhythmHeadline(minutes: rhythmMinutes.reduce(0, +)),
            actionHint: rhythmActionHint(minutes: rhythmMinutes)
        )

        let summary14 = analyzer.summarize(
            sessions: sessions,
            now: now,
            config: TemporalInsightsConfig(lookbackDays: 14, bestWindowWidthHours: 2)
        )
        let momentum = makeMomentumCard(summary14: summary14)

        let followThrough = makeFollowThroughCard(
            tasks: tasks,
            todayStart: todayStart,
            tomorrowStart: tomorrowStart
        )

        let bottom = makeBottomSection(
            sessions: sessions,
            projects: projects,
            now: now,
            todayStart: todayStart,
            tomorrowStart: tomorrowStart
        )

        return InsightsDashboardModel(
            hero: hero,
            bestWindow: bestWindow,
            rhythm: rhythm,
            momentum: momentum,
            followThrough: followThrough,
            bottom: bottom
        )
    }
}

private extension InsightsService {
    func sumAllSessionSeconds(sessions: [FocusSession], now: Date) -> TimeInterval {
        sessions.reduce(0) { partial, session in
            let end = session.endedAt ?? now
            guard end > session.startedAt else { return partial }
            return partial + end.timeIntervalSince(session.startedAt)
        }
    }

    func sumOverlappingSeconds(
        sessions: [FocusSession],
        rangeStart: Date,
        rangeEnd: Date,
        now: Date
    ) -> TimeInterval {
        sessions.reduce(0) { partial, session in
            let end = session.endedAt ?? now
            let clippedStart = max(session.startedAt, rangeStart)
            let clippedEnd = min(end, rangeEnd)
            guard clippedEnd > clippedStart else { return partial }
            return partial + clippedEnd.timeIntervalSince(clippedStart)
        }
    }

    func summaryForPast14DaysExcludingToday(sessions: [FocusSession], todayStart: Date) -> TemporalInsightsSummary {
        let endOfYesterday = todayStart.addingTimeInterval(-1)
        return analyzer.summarize(
            sessions: sessions,
            now: endOfYesterday,
            config: TemporalInsightsConfig(lookbackDays: 14, bestWindowWidthHours: 2)
        )
    }

    func calmLaneWindowIfEligible(summary: TemporalInsightsSummary) -> CalmLaneWindow? {
        guard summary.activeDayCount >= 3,
              summary.totalFocusSeconds >= 7200,
              let best = summary.bestWindow else {
            return nil
        }
        return CalmLaneWindow(startHour: best.startHour, endHour: best.endHour)
    }

    func hourlyMinutes(from metrics: [TemporalInsightsSummary.HourMetric]) -> [Int] {
        let byHour = Dictionary(uniqueKeysWithValues: metrics.map { ($0.hour, $0.totalSeconds) })
        return (0..<24).map { hour in
            let seconds = byHour[hour] ?? 0
            return max(0, Int((seconds / 60).rounded()))
        }
    }

    func makeBestWindowCard(summary: TemporalInsightsSummary) -> InsightCardModel {
        guard let window = summary.bestWindow else {
            return InsightCardModel(
                title: "Best focus window",
                headline: "Still learning your lane",
                subheadline: "Add a few sessions to reveal this.",
                actionHint: "Try one block at a repeatable hour."
            )
        }

        return InsightCardModel(
            title: "Best focus window",
            headline: hourLaneLabel(start: window.startHour, end: window.endHour),
            subheadline: "Based on the last 14 days before today.",
            actionHint: "Use this lane for your next session."
        )
    }

    func makeMomentumCard(summary14: TemporalInsightsSummary) -> InsightCardModel {
        let snapshots = summary14.dailySnapshots.sorted { $0.dayStart < $1.dayStart }
        let previous = snapshots.prefix(7)
        let current = snapshots.suffix(7)

        let previousHours = previous.reduce(0) { $0 + $1.totalSeconds } / 3600
        let currentHours = current.reduce(0) { $0 + $1.totalSeconds } / 3600

        let previousAvg = previous.isEmpty ? 0 : previousHours / Double(previous.count)
        let currentAvg = current.isEmpty ? 0 : currentHours / Double(current.count)
        let delta = currentAvg - previousAvg

        let headline: String
        if abs(delta) < 0.05 {
            headline = "Steady vs last week"
        } else if delta > 0 {
            headline = String(format: "+%.1f h/day vs last week", delta)
        } else {
            headline = String(format: "%.1f h/day vs last week", delta)
        }

        return InsightCardModel(
            title: "Momentum",
            headline: headline,
            subheadline: String(format: "Now: %.1f h/day", currentAvg),
            actionHint: delta >= 0
                ? "You are in rhythm. Keep one block protected."
                : "One short block today can lift this trend."
        )
    }

    func makeFollowThroughCard(tasks: [FocusTask], todayStart: Date, tomorrowStart: Date) -> InsightCardModel {
        let dueToday = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= todayStart && dueDate < tomorrowStart
        }
        let dueTodayCount = dueToday.count
        let doneTodayCount = dueToday.filter(\.isCompleted).count

        let overdueOpenCount = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate < todayStart && !task.isCompleted
        }.count

        let headline: String
        if dueTodayCount == 0 {
            headline = "No tasks due today"
        } else {
            headline = "\(doneTodayCount)/\(dueTodayCount) due today done"
        }

        let subheadline: String
        if overdueOpenCount > 0 {
            subheadline = "\(overdueOpenCount) overdue still open"
        } else {
            subheadline = "No overdue tasks right now"
        }

        let actionHint: String
        if overdueOpenCount > 0 {
            actionHint = "Clear one overdue item to lighten today."
        } else if dueTodayCount > 0 {
            actionHint = "Finish one small task next."
        } else {
            actionHint = "If you add a task, keep it light and clear."
        }

        return InsightCardModel(
            title: "Follow-through",
            headline: headline,
            subheadline: subheadline,
            actionHint: actionHint
        )
    }

    func makeBottomSection(
        sessions: [FocusSession],
        projects: [Project],
        now: Date,
        todayStart: Date,
        tomorrowStart: Date
    ) -> BottomSectionModel {
        let projectsWithGoals = projects.filter { $0.canTrackWeeklyGoal && ($0.weeklyGoalHours ?? 0) > 0 }

        if !projectsWithGoals.isEmpty {
            let totalWeeklyGoalHours = projectsWithGoals.reduce(0) { partial, project in
                partial + max(0, project.weeklyGoalHours ?? 0)
            }
            let goalSessions = sessions.filter {
                guard let project = $0.project else { return false }
                return project.canTrackWeeklyGoal && (project.weeklyGoalHours ?? 0) > 0
            }
            let projection = analyzer.weeklyGoalProjection(
                sessions: goalSessions,
                weeklyGoalHours: totalWeeklyGoalHours,
                now: now
            )

            let actualHours = projection?.actualHours ?? 0
            let recommendedToday = projection?.todayRecommendedHours ?? max(0, totalWeeklyGoalHours / 7)
            let additionalNeeded = projection?.todayAdditionalHoursNeeded ?? 0

            let model = WeeklyPaceModel(
                title: "Weekly pace",
                headline: String(format: "%.1f/%.1f h this week", actualHours, totalWeeklyGoalHours),
                subheadline: String(format: "Today recommendation: %.1f h", recommendedToday),
                actionHint: additionalNeeded > 0
                    ? "A short block today keeps you on pace."
                    : "On pace. A light check-in keeps it steady."
            )
            return .weeklyPace(model)
        }

        let summary30 = analyzer.summarize(
            sessions: sessions,
            now: now,
            config: TemporalInsightsConfig(lookbackDays: 30, bestWindowWidthHours: 2)
        )
        let longestToday = longestSessionOverlapToday(
            sessions: sessions,
            todayStart: todayStart,
            tomorrowStart: tomorrowStart,
            now: now
        )

        let streak = summary30.dailyStreakCount
        let streakLabel = streak == 1 ? "1 day streak" : "\(streak) day streak"
        let longestLabel = longestToday > 0
            ? "Longest session today: \(formatDuration(seconds: longestToday))"
            : "No session logged today yet"

        let model = ConsistencySnapshotModel(
            title: "Consistency snapshot",
            headline: streakLabel,
            subheadline: longestLabel,
            actionHint: "Small daily sessions build steady momentum."
        )
        return .consistency(model)
    }

    func longestSessionOverlapToday(
        sessions: [FocusSession],
        todayStart: Date,
        tomorrowStart: Date,
        now: Date
    ) -> TimeInterval {
        sessions.reduce(0) { longest, session in
            let end = session.endedAt ?? now
            let clippedStart = max(session.startedAt, todayStart)
            let clippedEnd = min(end, tomorrowStart)
            guard clippedEnd > clippedStart else { return longest }
            return max(longest, clippedEnd.timeIntervalSince(clippedStart))
        }
    }

    func formatFocusedToday(seconds: TimeInterval) -> String {
        if seconds < 3600 {
            let minutes = max(0, Int((seconds / 60).rounded()))
            return "\(minutes) min"
        }
        return String(format: "%.1f h", seconds / 3600)
    }

    func formatHours(_ seconds: TimeInterval) -> String {
        String(format: "%.1f h", max(0, seconds) / 3600)
    }

    func formatDuration(seconds: TimeInterval) -> String {
        if seconds < 3600 {
            let minutes = max(0, Int((seconds / 60).rounded()))
            return "\(minutes) min"
        }
        return String(format: "%.1f h", seconds / 3600)
    }

    func hourLaneLabel(start: Int, end: Int) -> String {
        String(format: "%02d:00-%02d:00", max(0, start), max(0, end))
    }

    func rhythmHeadline(minutes: Int) -> String {
        if minutes <= 0 {
            return "No focus logged yet today"
        }
        if minutes < 60 {
            return "\(minutes) min focused today"
        }
        return String(format: "%.1f h focused today", Double(minutes) / 60)
    }

    func rhythmActionHint(minutes: [Int]) -> String {
        let peakMinute = minutes.max() ?? 0
        if peakMinute == 0 {
            return "Your rhythm strip fills in as sessions are logged."
        }
        return "The tallest bars mark your most active hours."
    }
}
