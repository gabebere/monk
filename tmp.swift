import ManagedSettings

@available(iOS 16.0, *)
func makeToken() {
    let app = ManagedSettings.Application(bundleIdentifier: "com.apple.facetime")
    print(app)
    print(String(describing: app.token))
}
