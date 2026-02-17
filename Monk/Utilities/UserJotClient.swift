import Foundation
import OSLog
#if canImport(UserJot)
import UserJot
#endif

enum UserJotClient {
    private static let logger = Logger(subsystem: "com.gbr.Monk", category: "UserJot")
    private static let fallbackEmailDomain = "no-email.monk.app"

    /// Presents the UserJot feedback board if the SDK is available.
    /// - Returns: true if a presentation attempt was made.
    @discardableResult
    static func presentFeedbackBoard(board: String? = nil) -> Bool {
#if canImport(UserJot)
        logger.debug("Presenting UserJot feedback board \(board ?? "default", privacy: .public)")
        if let board {
            UserJot.showFeedback(board: board)
        } else {
            UserJot.showFeedback()
        }
        return true
#else
        logger.error("UserJot SDK not available in this build; feedback board not presented.")
        return false
#endif
    }

    static func identify(userId: String?, name: String?, email: String?) {
#if canImport(UserJot)
        guard let userId else { return }
        let components = name?.split(separator: " ").map(String.init) ?? []
        let firstName = components.first
        let lastName = components.dropFirst().joined(separator: " ")
        let resolvedEmail = email ?? fallbackEmail(for: userId)
        logger.debug("UserJot identify user hasRealEmail=\(email != nil, privacy: .public)")
        UserJot.identify(
            userId: userId,
            email: resolvedEmail,
            firstName: firstName,
            lastName: lastName.isEmpty ? nil : lastName
        )
#endif
    }

    private static func fallbackEmail(for userId: String) -> String {
        let normalized = userId.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let localPart = String((normalized.isEmpty ? "anon" : normalized).prefix(32))
        return "\(localPart)@\(fallbackEmailDomain)"
    }
}
