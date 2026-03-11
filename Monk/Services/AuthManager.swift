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
    private let passwordUsers: [PasswordCredential] = [
        .init(email: "reviewer@monk.app", password: "Demo123!", displayName: "Review Account")
    ]

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
    private let knownUsersKey = "auth.knownUserIDs"

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

        if isAuthenticated,
           let restoredUserID = defaults.string(forKey: userIDKey),
           !restoredUserID.isEmpty {
            Analytics.identify(restoredUserID,
                               userProperties: analyticsTraits(name: displayName, email: userEmail))
            Task {
                await WelcomeEmailService.shared.sendWelcomeIfNeeded(
                    userID: restoredUserID,
                    email: userEmail,
                    firstName: firstName(from: displayName),
                    provider: SignInProvider.restored.rawValue,
                    isFirstSeenOnDevice: false
                )
            }
        }
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
                           email: email,
                           provider: .apple)
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
                           email: email,
                           provider: .google)
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
        Analytics.track("auth_signed_out", [
            "had_email": (currentUserEmail?.isEmpty == false)
        ])
        clearLocalAuthState(clearAllAppDefaults: false)
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
#endif
        logger.debug("Signed out locally")
    }

    func deleteAccount() {
        Analytics.track("auth_account_deleted", [
            "had_email": (currentUserEmail?.isEmpty == false)
        ])
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
                       email: match.email,
                       provider: .password)
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

    func completeSignIn(userID: String,
                        name: String?,
                        email: String?,
                        provider: SignInProvider) {
        let defaults = UserDefaults.standard
        let previousUserID = defaults.string(forKey: userIDKey)
        let previousName = defaults.string(forKey: nameKey)
        let previousEmail = defaults.string(forKey: emailKey)
        let sameUserAsBefore = previousUserID == userID

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? (sameUserAsBefore ? previousName : nil)
        let resolvedEmail = (trimmedEmail?.isEmpty == false ? trimmedEmail : nil) ?? (sameUserAsBefore ? previousEmail : nil)

        var knownUsers = Set(defaults.stringArray(forKey: knownUsersKey) ?? [])
        let isFirstSeenOnDevice = !knownUsers.contains(userID)
        knownUsers.insert(userID)

        defaults.set(true, forKey: accessKey)
        defaults.set(userID, forKey: userIDKey)
        defaults.set(Array(knownUsers).sorted(), forKey: knownUsersKey)

        if let resolvedName {
            defaults.set(resolvedName, forKey: nameKey)
        } else {
            defaults.removeObject(forKey: nameKey)
        }
        if let resolvedEmail {
            defaults.set(resolvedEmail, forKey: emailKey)
        } else {
            defaults.removeObject(forKey: emailKey)
        }
        isAuthenticated = true
        displayName = resolvedName
        userEmail = resolvedEmail

        Analytics.identify(userID,
                           userProperties: analyticsTraits(name: resolvedName, email: resolvedEmail),
                           userPropertiesSetOnce: [
                            "first_seen_on_device_at": iso8601Now(),
                            "signup_provider": provider.rawValue
                           ])
        Analytics.track("auth_signed_in", [
            "provider": provider.rawValue,
            "has_email": resolvedEmail != nil,
            "is_first_seen_on_device": isFirstSeenOnDevice
        ])

        Task {
            await WelcomeEmailService.shared.sendWelcomeIfNeeded(
                userID: userID,
                email: resolvedEmail,
                firstName: firstName(from: resolvedName),
                provider: provider.rawValue,
                isFirstSeenOnDevice: isFirstSeenOnDevice
            )
        }
    }

    func analyticsTraits(name: String?, email: String?) -> [String: Any] {
        var traits: [String: Any] = [:]
        if let name, !name.isEmpty {
            traits["name"] = name
        }
        if let email, !email.isEmpty {
            traits["email"] = email
        }
        return traits
    }

    func firstName(from fullName: String?) -> String? {
        guard let fullName else { return nil }
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private struct PasswordCredential {
    let email: String
    let password: String
    let displayName: String?
}

private enum SignInProvider: String {
    case apple
    case google
    case password
    case restored
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
