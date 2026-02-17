import Foundation
import SwiftData
import Combine
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class FocusManager: ObservableObject {
    @Published private(set) var currentSession: FocusSession?
    @Published private(set) var todayTotalSeconds: TimeInterval = 0

    private var timer: AnyCancellable?
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let insightsAnalyzer = InsightsAnalyzer()
    private let calendarIntegration = CalendarIntegration.shared
    private var focusScoreTickCounter = 0
    private var mirrorObserver: Any?
    private var foregroundObserver: Any?

    init(modelContext: ModelContext,
         calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.currentSession = fetchInProgressSession()
        recalcTodayTotal()
        startTicking()
        // Optionally purge short sessions on launch if the preference is enabled
        purgeShortSessionsIfNeeded()

        if let activeProject = currentSession?.project {
            _ = HardBlockManager.shared.activateHardBlock(for: activeProject)
        }
        SnapshotWriter.refresh(modelContext: modelContext, currentSession: currentSession)

        mirrorObserver = NotificationCenter.default.addObserver(
            forName: .mirrorSessionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentSession = self.fetchInProgressSession()
                self.recalcTodayTotal()
                self.enforceShieldsIfNeeded()
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.enforceShieldsIfNeeded()
            }
        }
    }

    deinit {
        timer?.cancel()
        if let mirrorObserver {
            NotificationCenter.default.removeObserver(mirrorObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    func start(project: Project? = nil, task: FocusTask? = nil, mood: Int? = nil) {
        guard currentSession == nil else { return }
        let resolvedProject = project ?? task?.project
        let session = FocusSession(startedAt: Date(),
                                   endedAt: nil,
                                   project: resolvedProject,
                                   task: task)
        modelContext.insert(session)
        guard modelContext.saveOrRollback() else { return }
        currentSession = session
        Haptics.heavy()
        Task {
            await MirrorSyncService.shared.emitStart(for: session)
        }

#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let snapshot = currentFocusScoreSnapshot()
            LiveActivityManager.shared.startActivity(for: session, focusSnapshot: snapshot)
        }
#endif
        focusScoreTickCounter = 0

        if let resolvedProject {
            _ = HardBlockManager.shared.activateHardBlock(for: resolvedProject)
        }
        SnapshotWriter.refresh(modelContext: modelContext, currentSession: session)
    }

    func stop() {
        guard let session = currentSession else { return }
        let activeProject = session.project
        session.endedAt = Date()
        let discardSession = shouldDiscard(session: session)
        Task {
            await MirrorSyncService.shared.emitStop(for: session)
        }
        if discardSession {
            modelContext.delete(session)
        }

        let preferences = (try? modelContext.fetch(FetchDescriptor<Preferences>()))?.first
        let calendarIdentifier = preferences?.calendarCalendarIdentifier
        let shouldLogCalendar = calendarIdentifier?.isEmpty == false && calendarLoggingEnabledOnThisDevice

        guard modelContext.saveOrRollback() else { return }
        currentSession = nil
        recalcTodayTotal()
        Haptics.success()

        SnapshotWriter.refresh(modelContext: modelContext, currentSession: session, stateOverride: .stopped)

        if activeProject != nil {
            HardBlockManager.shared.deactivateHardBlock()
        }
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.endActivity(for: session)
        }
#endif
        focusScoreTickCounter = 0

        if !discardSession {
            Task { @MainActor in
                await captureLocationAndSync(for: session, calendarIdentifier: calendarIdentifier, shouldLogCalendar: shouldLogCalendar)
            }
        }
    }

    func recalcTodayTotal(now: Date = .now) {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return }

        // Fetch sessions overlapping today (not only those that started today)
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { s in
                s.startedAt < startOfTomorrow && (s.endedAt == nil || s.endedAt! >= startOfToday)
            },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []

        var total: TimeInterval = 0
        for s in sessions {
            let segStart = max(s.startedAt, startOfToday)
            let segEnd = min(s.endedAt ?? now, startOfTomorrow)
            if segEnd > segStart { total += segEnd.timeIntervalSince(segStart) }
        }
        todayTotalSeconds = total
    }

    private func fetchInProgressSession() -> FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { s in s.endedAt == nil }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func enforceShieldsIfNeeded() {
        if let project = currentSession?.project {
            _ = HardBlockManager.shared.activateHardBlock(for: project)
        }
    }

    private func weekBounds(containing date: Date) -> (start: Date, end: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysSinceSunday = weekday - 1
        let weekStart = calendar.date(byAdding: .day, value: -daysSinceSunday, to: startOfDay) ?? startOfDay
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? startOfDay
        return (weekStart, weekEnd)
    }

    private func startTicking() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.currentSession != nil { self.recalcTodayTotal() }
#if canImport(ActivityKit)
                if #available(iOS 16.2, *), let session = self.currentSession {
                    self.focusScoreTickCounter += 1
                    if self.focusScoreTickCounter >= 5 {
                        self.focusScoreTickCounter = 0
                        let snapshot = self.currentFocusScoreSnapshot()
                        LiveActivityManager.shared.updateActivity(for: session, focusSnapshot: snapshot)
                    } else {
                        LiveActivityManager.shared.updateActivity(for: session, focusSnapshot: nil)
                    }
                }
#endif
                self.objectWillChange.send() // keep timer updates flowing
            }
    }

    private func currentFocusScoreSnapshot(now: Date = .now) -> FocusScoreSnapshot? { nil }

}
// MARK: - Short session handling
extension FocusManager {
    private var shortThresholdSeconds: TimeInterval { 120 }

    private func shouldDiscard(session: FocusSession, now: Date = .now) -> Bool {
        let descriptor = FetchDescriptor<Preferences>()
        let prefs = (try? modelContext.fetch(descriptor))?.first
        guard prefs?.discardShortSessions == true else { return false }
        let dur = max(0, (session.endedAt ?? now).timeIntervalSince(session.startedAt))
        return dur < shortThresholdSeconds
    }

    func purgeShortSessionsIfNeeded(now: Date = .now) {
        let descriptor = FetchDescriptor<Preferences>()
        let prefs = (try? modelContext.fetch(descriptor))?.first
        guard prefs?.discardShortSessions == true else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        var didDelete = false
        for s in all {
            guard let end = s.endedAt else { continue }
            let dur = max(0, end.timeIntervalSince(s.startedAt))
            if dur < shortThresholdSeconds {
                modelContext.delete(s)
                didDelete = true
            }
        }
        if didDelete, modelContext.saveOrRollback() {
            recalcTodayTotal(now: now)
        }
    }

    private func captureLocationAndSync(for session: FocusSession,
                                        calendarIdentifier: String?,
                                        shouldLogCalendar: Bool) async {
        if shouldLogCalendar {
            if let result = await LocationProvider.shared.requestLocation() {
                session.locationName = result.displayName
                session.locationLatitude = result.location.coordinate.latitude
                session.locationLongitude = result.location.coordinate.longitude
                _ = modelContext.saveOrRollback()
            }

            if let calendarIdentifier,
               !calendarIdentifier.isEmpty {
                await CalendarIntegration.shared.logSession(session, calendarIdentifier: calendarIdentifier)
                let allSessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? [session]
                await CalendarIntegration.shared.backfillSessions(allSessions, calendarIdentifier: calendarIdentifier)
                if session.locationName != nil || (session.locationLatitude != nil && session.locationLongitude != nil) {
                    await CalendarIntegration.shared.updateEventLocation(for: session, calendarIdentifier: calendarIdentifier)
                }
            }
        }
    }

    private var calendarLoggingEnabledOnThisDevice: Bool {
        if let value = UserDefaults.standard.object(forKey: "calendar.logging.enabled") as? Bool {
            return value
        }
        return true
    }
}

extension FocusManager {
    func totalDuration(for project: Project, now: Date = .now) -> TimeInterval {
        project.totalDuration(now: now)
    }

    func lastActivityDate(for project: Project) -> Date? {
        project.mostRecentSessionDate
    }

    func weeklyGoalProgress(for project: Project, now: Date = .now) -> ProjectGoalProgress {
        let (weekStart, weekEnd) = weekBounds(containing: now)
        let sessions = project.sessions ?? []
        var total: TimeInterval = 0
        for session in sessions {
            let sessionStart = session.startedAt
            let sessionEnd = session.endedAt ?? now
            if sessionEnd <= weekStart || sessionStart >= weekEnd { continue }
            let clampedStart = max(sessionStart, weekStart)
            let clampedEnd = min(sessionEnd, weekEnd)
            if clampedEnd > clampedStart {
                total += clampedEnd.timeIntervalSince(clampedStart)
            }
        }
        let goalSeconds = project.canTrackWeeklyGoal
            ? project.weeklyGoalHours.map { max(0, $0) * 3600 }
            : nil
        return ProjectGoalProgress(actualSeconds: total, goalSeconds: goalSeconds)
    }

}

struct ProjectGoalProgress {
    let actualSeconds: TimeInterval
    let goalSeconds: TimeInterval?

    var actualHours: Double { actualSeconds / 3600 }
    var goalHours: Double? { goalSeconds.map { $0 / 3600 } }
    var progressFraction: Double {
        guard let goal = goalSeconds, goal > 0 else { return 0 }
        return min(max(actualSeconds / goal, 0), 1)
    }
}
