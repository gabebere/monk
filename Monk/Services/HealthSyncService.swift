import Foundation
import HealthKit
import OSLog
import SwiftData

@MainActor
final class HealthSyncService {
    static let shared = HealthSyncService()

    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "HealthSync")
    private let lookbackDays: Double = 30

    private init() {}

    func syncOnLaunch(modelContext: ModelContext) {
        Task { await performSyncIfNeeded(modelContext: modelContext) }
    }

    func performSyncIfNeeded(modelContext: ModelContext, forceFullResync: Bool = false) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard calendarLoggingEnabledOnThisDevice else { return }

        let prefs = resolvePreferences(modelContext: modelContext)
        guard prefs.calendarIntegrationEnabled,
              let calendarId = prefs.calendarCalendarIdentifier,
              !calendarId.isEmpty else { return }

        let wantsWorkouts = prefs.healthIncludeWorkouts
        let wantsSleepInBed = prefs.healthIncludeSleepInBed
        let wantsSleepAsleep = prefs.healthIncludeSleepAsleep
        guard wantsWorkouts || wantsSleepInBed || wantsSleepAsleep else { return }

        guard await requestAuthorizationIfNeeded() else { return }

        let baseline = Date().addingTimeInterval(-lookbackDays * 86_400)
        let lastImport = forceFullResync ? nil : prefs.healthLastImportAt
        let windowStart = max(lastImport ?? baseline, baseline)

        if wantsWorkouts {
            await syncWorkouts(since: windowStart,
                               calendarId: calendarId,
                               defaultProjectId: prefs.healthDefaultWorkoutProjectId,
                               modelContext: modelContext)
        }

        if wantsSleepAsleep || wantsSleepInBed {
            await syncSleep(since: windowStart,
                            calendarId: calendarId,
                            includeInBed: wantsSleepInBed,
                            includeAsleep: wantsSleepAsleep,
                            modelContext: modelContext)
        }

        prefs.healthLastImportAt = Date()
        _ = modelContext.saveOrRollback()
    }

    func removeImportedEvents(kinds: [HealthSampleKind],
                              calendarId: String?,
                              modelContext: ModelContext) async {
        guard let calendarId, !calendarId.isEmpty else { return }
        let links = (try? modelContext.fetch(FetchDescriptor<HealthSampleLink>())) ?? []
        let allowed = Set(kinds.map(\.rawValue))
        for link in links {
            guard let kindRaw = link.kindRaw, allowed.contains(kindRaw) else { continue }
            if let eventId = link.eventIdentifier {
                await CalendarIntegration.shared.deleteEvent(identifier: eventId)
            }
            modelContext.delete(link)
        }
        if let prefs = (try? modelContext.fetch(FetchDescriptor<Preferences>()))?.first {
            prefs.healthLastImportAt = nil
        }
        _ = modelContext.saveOrRollback()
    }
}

// MARK: - Permissions

private extension HealthSyncService {
    func requestAuthorizationIfNeeded() async -> Bool {
        let shareTypes: Set<HKSampleType> = []
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return false }
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            sleepType
        ]

        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            logger.error("HealthKit auth failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

// MARK: - Workouts

private extension HealthSyncService {
    func syncWorkouts(since: Date,
                      calendarId: String,
                      defaultProjectId: UUID?,
                      modelContext: ModelContext) async {
        let workouts = await fetchWorkouts(since: since)
        guard !workouts.isEmpty else { return }
        for workout in workouts {
            let sampleId = workout.uuid.uuidString
            let link = resolveLink(id: sampleId,
                                   kind: .workout,
                                   modelContext: modelContext,
                                   start: workout.startDate,
                                   end: workout.endDate)
            link.projectId = defaultProjectId

            let title = workout.workoutActivityType.displayName
            let notes = """
            Monk imported from Health
            Sample: \(sampleId)
            Source: \(workout.sourceRevision.source.name)
            """
            let eventId = await CalendarIntegration.shared.upsertHealthEvent(
                existingIdentifier: link.eventIdentifier,
                calendarIdentifier: calendarId,
                title: title,
                start: workout.startDate,
                end: workout.endDate,
                notes: notes
            )
            link.eventIdentifier = eventId
            link.startDate = workout.startDate
            link.endDate = workout.endDate
            link.lastImportedAt = Date()
        }
        _ = modelContext.saveOrRollback()
    }

    func fetchWorkouts(since: Date) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    self.logger.error("Workout fetch failed: \(error.localizedDescription, privacy: .public)")
                }
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }
}

// MARK: - Sleep

private extension HealthSyncService {
    func syncSleep(since: Date,
                   calendarId: String,
                   includeInBed: Bool,
                   includeAsleep: Bool,
                   modelContext: ModelContext) async {
        guard includeInBed || includeAsleep else { return }
        let samples = await fetchSleepSamples(since: since)
        guard !samples.isEmpty else { return }
        logger.debug("HealthSync sleep: fetched \(samples.count, privacy: .public) samples since \(since, privacy: .public)")

        let calendar = Calendar(identifier: .gregorian)
        struct NightAggregate {
            var inBedIntervals: [(start: Date, end: Date)] = []
            var asleepIntervals: [(start: Date, end: Date)] = []
        }

        var nights: [Date: NightAggregate] = [:]
        for sample in samples {
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) ?? .inBed
            let nightKey = calendar.startOfDay(for: sample.startDate)
            var agg = nights[nightKey] ?? NightAggregate()
            switch value {
            case .inBed:
                agg.inBedIntervals.append((start: sample.startDate, end: sample.endDate))
            default:
                agg.asleepIntervals.append((start: sample.startDate, end: sample.endDate))
            }
            nights[nightKey] = agg
        }

        for (night, agg) in nights {
            logger.debug("HealthSync night \(night, privacy: .public): inBed=\(agg.inBedIntervals.count, privacy: .public) asleep=\(agg.asleepIntervals.count, privacy: .public)")
            let mergedAsleep = mergeIntervals(agg.asleepIntervals, maxGap: 30 * 60)
            let mergedLabel = mergedAsleep.map { [self] interval in
                intervalLabel(interval)
            }.joined(separator: ", ")
            logger.debug("HealthSync night \(night, privacy: .public): mergedAsleep=\(mergedLabel, privacy: .public)")
            let mergedCombined = mergeIntervals(agg.asleepIntervals + agg.inBedIntervals, maxGap: 30 * 60)
            let combinedLabel = mergedCombined.map { [self] interval in
                intervalLabel(interval)
            }.joined(separator: ", ")
            logger.debug("HealthSync night \(night, privacy: .public): mergedCombined=\(combinedLabel, privacy: .public)")
            if includeAsleep,
               let overallStart = mergedCombined.first?.start {
                let totalSeconds = mergedCombined.reduce(0) { $0 + duration($1) }
                guard totalSeconds > 0 else { continue }
                let eventEnd = overallStart.addingTimeInterval(totalSeconds)
                let spanEnd = mergedCombined.last?.end ?? eventEnd
                let durationLabel = durationString(totalSeconds)
                logger.debug("HealthSync night \(night, privacy: .public): final asleep interval \( self.intervalLabel((overallStart, eventEnd)), privacy: .public) total \(durationLabel, privacy: .public) span \(self.intervalLabel((overallStart, spanEnd)), privacy: .public)")
                let sampleId = nightKeyString(prefix: "sleep-asleep", night: night)
                let link = resolveLink(id: sampleId,
                                       kind: .sleepAsleep,
                                       modelContext: modelContext,
                                       start: overallStart,
                                       end: eventEnd)
                let notes = """
                Monk imported from Health
                Night: \(sampleId)
                Segments (asleep+in bed): \(combinedLabel)
                Span: \(intervalLabel((overallStart, spanEnd)))
                """
                let eventId = await CalendarIntegration.shared.upsertHealthEvent(
                    existingIdentifier: link.eventIdentifier,
                    calendarIdentifier: calendarId,
                    title: "Asleep (\(durationLabel))",
                    start: overallStart,
                    end: eventEnd,
                    notes: notes
                )
                link.eventIdentifier = eventId
                link.startDate = overallStart
                link.endDate = eventEnd
                link.lastImportedAt = Date()
            }

            if includeInBed,
               let firstAsleepStart = mergedAsleep.first?.start,
               let windDownStart = earliestStart(before: firstAsleepStart, intervals: agg.inBedIntervals),
               windDownStart < firstAsleepStart {
                logger.debug("HealthSync night \(night, privacy: .public): windDown \( self.intervalLabel((windDownStart, firstAsleepStart)), privacy: .public)")
                let sampleId = nightKeyString(prefix: "sleep-winddown", night: night)
                let link = resolveLink(id: sampleId,
                                       kind: .sleepInBed,
                                       modelContext: modelContext,
                                       start: windDownStart,
                                       end: firstAsleepStart)
                let notes = """
                Monk imported from Health
                Night: \(sampleId)
                """
                let eventId = await CalendarIntegration.shared.upsertHealthEvent(
                    existingIdentifier: link.eventIdentifier,
                    calendarIdentifier: calendarId,
                    title: "Wind Down in Bed",
                    start: windDownStart,
                    end: firstAsleepStart,
                    notes: notes
                )
                link.eventIdentifier = eventId
                link.startDate = windDownStart
                link.endDate = firstAsleepStart
                link.lastImportedAt = Date()
            }
        }

        _ = modelContext.saveOrRollback()
    }

    func fetchSleepSamples(since: Date) async -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: sleepType,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    self.logger.error("Sleep fetch failed: \(error.localizedDescription, privacy: .public)")
                }
                let results = samples as? [HKCategorySample] ?? []
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }
}

// MARK: - Helpers

private extension HealthSyncService {
    func resolvePreferences(modelContext: ModelContext) -> Preferences {
        if let prefs = (try? modelContext.fetch(FetchDescriptor<Preferences>()))?.first {
            return prefs
        }
        let prefs = Preferences(hasConvertedDailyGoal: true)
        modelContext.insert(prefs)
        return prefs
    }

    func resolveLink(id: String,
                     kind: HealthSampleKind,
                     modelContext: ModelContext,
                     start: Date,
                     end: Date) -> HealthSampleLink {
        let descriptor = FetchDescriptor<HealthSampleLink>(
            predicate: #Predicate { $0.sampleId == id }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.kind = kind
            return existing
        }
        let link = HealthSampleLink(sampleId: id,
                                    kind: kind,
                                    startDate: start,
                                    endDate: end,
                                    lastImportedAt: Date())
        modelContext.insert(link)
        return link
    }

    var calendarLoggingEnabledOnThisDevice: Bool {
        if let value = UserDefaults.standard.object(forKey: "calendar.logging.enabled") as? Bool {
            return value
        }
        return true
    }

    func minDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return min(lhs, rhs)
    }

    func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }

    func earliestStart(before cutoff: Date, intervals: [(start: Date, end: Date)]) -> Date? {
        intervals
            .filter { $0.start < cutoff }
            .min { $0.start < $1.start }?
            .start
    }

    func mergeIntervals(_ intervals: [(start: Date, end: Date)], maxGap: TimeInterval) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        var current = sorted.first!
        for interval in sorted.dropFirst() {
            if interval.start.timeIntervalSince(current.end) <= maxGap {
                current.end = max(current.end, interval.end)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    func duration(_ interval: (start: Date, end: Date)) -> TimeInterval {
        interval.end.timeIntervalSince(interval.start)
    }

    func durationString(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(max(0, seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }

    func nightKeyString(prefix: String, night: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return "\(prefix)-\(formatter.string(from: night))"
    }

    func intervalLabel(_ interval: (start: Date, end: Date)) -> String {
        "\(shortDate(interval.start)) → \(shortDate(interval.end))"
    }

    func shortDate(_ date: Date) -> String {
        Self.intervalFormatter.string(from: date)
    }

    static let intervalFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        return f
    }()
}

private extension HKWorkoutActivityType {
    var displayName: String {
        let names: [UInt: String] = [
            1: "American Football",
            2: "Archery",
            3: "Australian Football",
            4: "Badminton",
            5: "Baseball",
            6: "Basketball",
            7: "Bowling",
            8: "Boxing",
            9: "Climbing",
            10: "Cricket",
            11: "Cross Training",
            12: "Curling",
            13: "Cycling",
            14: "Dance",
            15: "Dance Inspired Training",
            16: "Elliptical",
            17: "Equestrian Sports",
            18: "Fencing",
            19: "Fishing",
            20: "Functional Strength",
            21: "Golf",
            22: "Gymnastics",
            23: "Handball",
            24: "Hiking",
            25: "Hockey",
            26: "Hunting",
            27: "Lacrosse",
            28: "Martial Arts",
            29: "Mind & Body",
            30: "Mixed Metabolic Cardio",
            31: "Paddle Sports",
            32: "Play",
            33: "Preparation & Recovery",
            34: "Racket Sports",
            35: "Rowing",
            36: "Rugby",
            37: "Running",
            38: "Sailing",
            39: "Skating Sports",
            40: "Snow Sports",
            41: "Soccer",
            42: "Softball",
            43: "Squash",
            44: "Stair Climbing",
            45: "Surfing",
            46: "Swimming",
            47: "Table Tennis",
            48: "Tennis",
            49: "Track & Field",
            50: "Strength Training",
            51: "Volleyball",
            52: "Walking",
            53: "Water Fitness",
            54: "Water Polo",
            55: "Water Sports",
            56: "Wrestling",
            57: "Yoga",
            58: "Barre",
            59: "Core Training",
            60: "Cross Country Skiing",
            61: "Downhill Skiing",
            62: "Flexibility",
            63: "HIIT",
            64: "Jump Rope",
            65: "Kickboxing",
            66: "Pilates",
            67: "Snowboarding",
            68: "Stairs",
            69: "Step Training",
            70: "Weightlifting",
            71: "Wheelchair Walk Pace",
            72: "Wheelchair Run Pace",
            73: "Tai Chi",
            74: "Mixed Cardio",
            75: "Hand Cycling",
            76: "Disc Sports",
            77: "Fitness Gaming",
            78: "Pickleball",
            79: "Climbing Sport"
        ]
        return names[rawValue] ?? "Workout \(rawValue)"
    }
}
