import Foundation
import SwiftData
import Combine
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
    private var focusScoreTickCounter = 0

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
            if !HardBlockManager.shared.activateHardBlock(for: activeProject) {
                reapplySoftBlockFromPreferences()
            }
        } else {
            reapplySoftBlockFromPreferences()
        }
    }

    func start(project: Project? = nil, mood: Int? = nil) {
        guard currentSession == nil else { return }
        let session = FocusSession(startedAt: Date(),
                                   endedAt: nil,
                                   moodScore: mood,
                                   project: project)
        modelContext.insert(session)
        try? modelContext.save()
        currentSession = session
        Haptics.light()

#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let snapshot = currentFocusScoreSnapshot()
            LiveActivityManager.shared.startActivity(for: session, focusSnapshot: snapshot)
        }
#endif
        focusScoreTickCounter = 0

        if let project {
            _ = HardBlockManager.shared.activateHardBlock(for: project)
        }
    }

    func stop() {
        guard let session = currentSession else { return }
        let activeProject = session.project
        session.endedAt = Date()
        try? modelContext.save()
        // Discard session if shorter than threshold and preference is enabled
        if shouldDiscard(session: session) {
            modelContext.delete(session)
            try? modelContext.save()
        }
        currentSession = nil
        recalcTodayTotal()
        Haptics.success()

        if activeProject != nil {
            HardBlockManager.shared.deactivateHardBlock()
        }
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.endActivity(for: session)
        }
#endif
        focusScoreTickCounter = 0
        reapplySoftBlockFromPreferences()
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

    private func currentFocusScoreSnapshot(now: Date = .now) -> FocusScoreSnapshot? {
        let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        guard !sessions.isEmpty else { return nil }
        let prefs = (try? modelContext.fetch(FetchDescriptor<Preferences>()))
            .flatMap { $0.first }
        let weeklyGoal = prefs?.weeklyGoalHours
        return insightsAnalyzer.focusScore(sessions: sessions, weeklyGoalHours: weeklyGoal, now: now)
    }

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
        if didDelete { try? modelContext.save(); recalcTodayTotal(now: now) }
    }
}

extension FocusManager {
    func totalDuration(for project: Project, now: Date = .now) -> TimeInterval {
        project.totalDuration(now: now)
    }

    func lastActivityDate(for project: Project) -> Date? {
        project.mostRecentSessionDate
    }

    private func reapplySoftBlockFromPreferences() {
        let descriptor = FetchDescriptor<Preferences>()
        guard let prefs = (try? modelContext.fetch(descriptor))?.first else { return }
        let selection = SoftBlockManager.shared.decodeSelection(from: prefs.softBlockSelectionData)
        SoftBlockManager.shared.apply(selection: selection, enabled: prefs.softBlockEnabled)
    }
}
