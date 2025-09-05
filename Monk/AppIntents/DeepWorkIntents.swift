import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, *)
struct StartDeepWorkIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Deep Work"
    static var description = IntentDescription("Start a deep work session without opening the app.")

    func perform() async throws -> some IntentResult {
        let context = try Self.makeContext()
        // If an in-progress session exists, do nothing
        let inProgress = try? context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.endedAt == nil })).first
        if inProgress == nil {
            let session = FocusSession(startedAt: Date(), endedAt: nil)
            context.insert(session)
            try? context.save()
            if #available(iOS 16.1, *), NSClassFromString("ActivityKit.Activity") != nil {
                LiveActivityManager.start(startedAt: session.startedAt)
            }
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct StopDeepWorkIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Deep Work"
    static var description = IntentDescription("Stop the current deep work session.")

    func perform() async throws -> some IntentResult {
        let context = try Self.makeContext()
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.endedAt == nil })
        if let current = try? context.fetch(descriptor).first {
            current.endedAt = Date()
            try? context.save()
            if #available(iOS 16.1, *), NSClassFromString("ActivityKit.Activity") != nil {
                LiveActivityManager.end()
            }
        }
        return .result()
    }
}

// Note: Gallery tiles (AppShortcutsProvider) differ across SDKs.
// To avoid compiler mismatch across Xcode versions, providers are omitted for now.
// The intents remain discoverable in Shortcuts search. Provide your Xcode/iOS SDK
// and I will add the correct provider signature for your environment.

@available(iOS 16.0, *)
extension StartDeepWorkIntent {
    static func makeContext() throws -> ModelContext {
        let schema = Schema([FocusSession.self, Preferences.self])
        let container = try ModelContainer(for: schema)
        return ModelContext(container)
    }
}

@available(iOS 16.0, *)
extension StopDeepWorkIntent {
    static func makeContext() throws -> ModelContext {
        let schema = Schema([FocusSession.self, Preferences.self])
        let container = try ModelContainer(for: schema)
        return ModelContext(container)
    }
}
