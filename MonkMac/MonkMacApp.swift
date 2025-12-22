import SwiftUI
import SwiftData
import MonkShared
import RevenueCat
#if canImport(UserJot)
import UserJot
#endif
import OSLog

@main
struct MonkMacApp: App {
    init() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        HardBlockStateStore.bootstrap()
        #endif
        configureRevenueCat()
        Analytics.configure()
        #if canImport(UserJot)
        UserJot.setup(projectId: "cmiptfvv400yb15lbz1dzqbey")
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        let logger = Logger(subsystem: "com.gbr.Monk", category: "Persistence")
        let schema = Schema([
            FocusSession.self,
            Preferences.self,
            Project.self
        ])
        do {
            let configuration = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.gbr.Monk")
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("Failed to create CloudKit-backed ModelContainer: \(error.localizedDescription, privacy: .public)")
            let fallbackConfiguration = ModelConfiguration(isStoredInMemoryOnly: false)
            do {
                logger.info("Falling back to on-device ModelContainer storage.")
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                logger.critical("Failed to create fallback ModelContainer: \(error.localizedDescription, privacy: .public)")
                fatalError("Unable to create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            MacContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

private extension MonkMacApp {
    func configureRevenueCat() {
        Purchases.logLevel = .warn
        Purchases.configure(
            with: .init(withAPIKey: "appl_MdQJjbrjYFxzEaabiQbrRLrmDZc")
        )
    }
}
