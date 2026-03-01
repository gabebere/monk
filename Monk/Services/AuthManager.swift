import Foundation
import AuthenticationServices
import OSLog
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class AuthManager: ObservableObject {
    private let logger = Logger(subsystem: "com.gbr.Monk", category: "AuthManager")
    private let googleClientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
#if DEBUG
    private let passwordUsers: [PasswordCredential] = [
        .init(email: "reviewer@monk.app", password: "Demo123!", displayName: "Review Account")
    ]
#else
    private let passwordUsers: [PasswordCredential] = []
#endif

    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var displayName: String?
    @Published private(set) var userEmail: String?
    @Published private(set) var newsletterEmail: String?
    @Published private(set) var newsletterOptIn: Bool = false

    private let accessKey = "auth.isAuthenticated"
    private let userIDKey = "auth.userID"
    private let nameKey = "auth.name"
    private let emailKey = "auth.email"
    private let newsletterEmailKey = "auth.newsletterEmail"
    private let newsletterOptInKey = "auth.newsletterOptIn"

    init() {
        let defaults = UserDefaults.standard
        self.isAuthenticated = defaults.bool(forKey: accessKey)
        self.displayName = defaults.string(forKey: nameKey)
        self.userEmail = defaults.string(forKey: emailKey)
        self.newsletterEmail = defaults.string(forKey: newsletterEmailKey)
        self.newsletterOptIn = defaults.bool(forKey: newsletterOptInKey)

#if canImport(GoogleSignIn)
        if let googleClientID, !googleClientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
        } else {
            logger.error("Missing GIDClientID in Info.plist; Google sign-in is disabled.")
        }
#endif
    }

    var currentUserId: String? {
        UserDefaults.standard.string(forKey: userIDKey)
    }

    var currentUserEmail: String? {
        UserDefaults.standard.string(forKey: emailKey)
    }

    func handleAppleAuthorization(_ authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let userID = credential.user
            let email = credential.email
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            completeSignIn(userID: userID,
                           name: name.isEmpty ? nil : name,
                           email: email)
            if email == nil {
                logger.debug("Apple sign-in returned no email (likely re-auth).")
            }
        }
    }

    func signInWithGoogle(presenting viewController: UIViewController) async -> Result<Void, Error> {
#if canImport(GoogleSignIn)
        guard GIDSignIn.sharedInstance.configuration != nil else {
            return .failure(PasswordAuthError.googleUnavailable)
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            let user = result.user
            let name = [user.profile?.givenName, user.profile?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let email = user.profile?.email
            completeSignIn(userID: user.userID ?? UUID().uuidString,
                           name: name.isEmpty ? nil : name,
                           email: email)
            return .success(())
        } catch {
            return .failure(error)
        }
#else
        struct GoogleUnavailable: LocalizedError {
            var errorDescription: String? { "GoogleSignIn SDK not linked in this build." }
        }
        return .failure(GoogleUnavailable())
#endif
    }

    func signOut() {
        clearLocalAuthState(clearAllAppDefaults: false)
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
#endif
        logger.debug("Signed out locally")
    }

    func deleteAccount() {
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.disconnect { _ in }
#endif
        clearLocalAuthState(clearAllAppDefaults: true)
        Analytics.reset()
        logger.info("Deleted account and local data")
    }

    func applyNewsletterPreference(email: String?, optedIn: Bool) {
        let defaults = UserDefaults.standard
        if optedIn {
            let finalEmail = email ?? currentUserEmail
            defaults.set(finalEmail, forKey: newsletterEmailKey)
            defaults.set(true, forKey: newsletterOptInKey)
            newsletterEmail = finalEmail
            newsletterOptIn = true
        } else {
            defaults.removeObject(forKey: newsletterEmailKey)
            defaults.set(false, forKey: newsletterOptInKey)
            newsletterEmail = nil
            newsletterOptIn = false
        }
    }

    func signInWithPassword(email: String, password: String) -> Result<Void, Error> {
        guard !passwordUsers.isEmpty else {
            return .failure(PasswordAuthError.unavailable)
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = passwordUsers.first(where: { $0.email.caseInsensitiveCompare(trimmedEmail) == .orderedSame }) else {
            return .failure(PasswordAuthError.invalid)
        }
        guard match.password == password else {
            return .failure(PasswordAuthError.invalid)
        }
        completeSignIn(userID: "password:\(match.email.lowercased())",
                       name: match.displayName,
                       email: match.email)
        return .success(())
    }
}

private extension AuthManager {
    func clearLocalAuthState(clearAllAppDefaults: Bool) {
        let defaults = UserDefaults.standard
        if clearAllAppDefaults,
           let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }
        defaults.removeObject(forKey: accessKey)
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: emailKey)
        defaults.removeObject(forKey: newsletterEmailKey)
        defaults.removeObject(forKey: newsletterOptInKey)
        isAuthenticated = false
        displayName = nil
        userEmail = nil
        newsletterEmail = nil
        newsletterOptIn = false
    }

    func completeSignIn(userID: String, name: String?, email: String?) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: accessKey)
        defaults.set(userID, forKey: userIDKey)
        if let name {
            defaults.set(name, forKey: nameKey)
        } else {
            defaults.removeObject(forKey: nameKey)
        }
        if let email {
            defaults.set(email, forKey: emailKey)
        } else {
            defaults.removeObject(forKey: emailKey)
        }
        isAuthenticated = true
        displayName = name
        userEmail = email
    }
}

private struct PasswordCredential {
    let email: String
    let password: String
    let displayName: String?
}

enum PasswordAuthError: LocalizedError {
    case invalid
    case unavailable
    case googleUnavailable

    var errorDescription: String? {
        switch self {
        case .invalid:
            return "Invalid email or password."
        case .unavailable:
            return "Email/password sign-in is not available in this build."
        case .googleUnavailable:
            return "Google sign-in is unavailable in this build."
        }
    }
}
