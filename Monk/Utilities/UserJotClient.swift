import Foundation
#if canImport(UserJot)
import UserJot
#endif

enum UserJotClient {
    /// Temporary override to force an email when the provider doesn’t return one (e.g., Apple re-auth).
    /// Replace with a safer capture once login flow is fixed.
    private static let forcedFallbackEmail = "gabriel@monk.app"

    /// Presents the UserJot feedback board if the SDK is available.
    /// - Returns: true if a presentation attempt was made.
    @discardableResult
    static func presentFeedbackBoard(board: String? = nil) -> Bool {
#if canImport(UserJot)
        print("[UserJot] presentFeedbackBoard board=\(board ?? "default")")
        print("[UserJot] SDK version unknown (no API), project setup happens in MonkApp")
        if let board {
            UserJot.showFeedback(board: board)
        } else {
            UserJot.showFeedback()
        }
        return true
#else
        print("UserJot SDK not available in this build; feedback board not presented.")
        return false
#endif
    }

    static func identify(userId: String?, name: String?, email: String?) {
#if canImport(UserJot)
        guard let userId else { return }
        let components = name?.split(separator: " ").map(String.init) ?? []
        let firstName = components.first
        let lastName = components.dropFirst().joined(separator: " ")
        let resolvedEmail = email ?? forcedFallbackEmail
        print("[UserJot] identify id=\(userId), email=\(resolvedEmail), first=\(firstName ?? "nil"), last=\(lastName)")
        UserJot.identify(
            userId: userId,
            email: resolvedEmail,
            firstName: firstName,
            lastName: lastName.isEmpty ? nil : lastName
        )
#endif
    }
}
