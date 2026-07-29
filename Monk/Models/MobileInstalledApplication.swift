import ManagedSettings

struct MobileInstalledApplication: Identifiable, Hashable {
    let token: ManagedSettings.ApplicationToken
    let displayName: String
    let bundleIdentifier: String?

    var id: ManagedSettings.ApplicationToken { token }
}
