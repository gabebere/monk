import Foundation
import OSLog
#if canImport(SwiftData)
import SwiftData
#endif

enum SnapshotWriter {
    private static let logger = Logger(subsystem: "com.gbr.Monk", category: "SnapshotWriter")

    static func write(_ snapshot: LiveSnapshot) {
        guard let url = SnapshotStorage.containerURL?.appendingPathComponent(SnapshotStorage.snapshotFileName) else { return }
        do {
            let data = try SnapshotStorage.encoder.encode(snapshot)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            SnapshotStorage.userDefaults?.set(data, forKey: SnapshotStorage.userDefaultsKey)
        } catch {
            logger.error("Snapshot write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func update(using builder: (inout LiveSnapshot) -> Void) {
        var snapshot = SnapshotReader.load()
        builder(&snapshot)
        snapshot.lastUpdatedAt = Date()
        write(snapshot)
    }

#if canImport(SwiftData)
    static func refresh(modelContext: ModelContext,
                        currentSession: FocusSession?,
                        stateOverride: TimerSnapshotState? = nil,
                        now: Date = .now) {
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        let analyzer = InsightsAnalyzer()
        let goalsSummary = analyzer.weeklyProjectGoals(projects: projects, sessions: sessions, now: now)
        let goalsSnapshot = goalsSummary.hasGoals ? mapSummary(goalsSummary) : nil

        let resolvedState: TimerSnapshotState = {
            if let override = stateOverride { return override }
            guard let session = currentSession else { return .idle }
            return session.endedAt == nil ? .running : .paused
        }()

        let resolvedSession = currentSession
        let elapsed: TimeInterval = {
            guard let session = resolvedSession else { return 0 }
            return max(0, (session.endedAt ?? now).timeIntervalSince(session.startedAt))
        }()

        let projectProgress = weeklyProgress(for: resolvedSession?.project ?? resolvedSession?.task?.project, now: now)

        let snapshot = LiveSnapshot(
            sessionID: resolvedSession?.id,
            taskTitle: resolvedSession?.task?.displayTitle ?? resolvedSession?.task?.title,
            projectTitle: resolvedSession?.project?.title ?? resolvedSession?.task?.project?.title,
            timerState: resolvedState,
            timerStart: resolvedSession?.startedAt,
            timerEnd: resolvedSession?.endedAt ?? now,
            elapsedSeconds: elapsed,
            weeklyGoalSeconds: projectProgress.goal,
            weeklyCompletedSeconds: projectProgress.completed,
            weeklyRemainingSeconds: projectProgress.remaining,
            todayGoalSeconds: nil,
            todayCompletedSeconds: nil,
            todayRemainingSeconds: nil,
            projectGoals: goalsSnapshot,
            lastUpdatedAt: now
        )
        write(snapshot)
    }

    private static func mapSummary(_ summary: WeeklyProjectGoalSummary) -> WeeklyGoalsSnapshot {
        let segments = summary.segments.map {
            WeeklyGoalsSnapshot.Segment(
                id: $0.id,
                title: $0.title,
                gradientIndex: $0.gradientIndex,
                goalHours: $0.goalHours,
                actualHours: $0.actualHours
            )
        }
        return WeeklyGoalsSnapshot(
            weekStart: summary.weekStart,
            weekEnd: summary.weekEnd,
            rawGoalHours: summary.rawGoalHours,
            totalGoalHours: summary.totalGoalHours,
            scaleFactor: summary.scaleFactor,
            segments: segments
        )
    }

    private static func weeklyProgress(for project: Project?, now: Date) -> (goal: TimeInterval?, completed: TimeInterval?, remaining: TimeInterval?) {
        guard let project else { return (nil, nil, nil) }
        let goalSeconds = project.weeklyGoalHours.map { max(0, $0) * 3600 }
        let sessions = project.sessions ?? []
        let bounds = weekBounds(containing: now)
        var total: TimeInterval = 0
        for session in sessions {
            let end = session.endedAt ?? now
            if end <= bounds.start || session.startedAt >= bounds.end { continue }
            let clippedStart = max(session.startedAt, bounds.start)
            let clippedEnd = min(end, bounds.end)
            if clippedEnd > clippedStart {
                total += clippedEnd.timeIntervalSince(clippedStart)
            }
        }
        let remaining = goalSeconds.flatMap { max(0, $0 - total) }
        return (goalSeconds, total, remaining)
    }

    private static func weekBounds(containing date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        let startOfDay = calendar.startOfDay(for: date)
        let interval = calendar.dateInterval(of: .weekOfYear, for: startOfDay)
        let start = interval?.start ?? startOfDay
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? startOfDay
        return (start, end)
    }
#endif
}
