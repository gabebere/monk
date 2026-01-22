import Foundation
import AuthenticationServices
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class AuthManager: ObservableObject {
    private let googleClientID = "767517007770-v4i7a49e9qi2b3tmgpgu7s1nrtmf9enb.apps.googleusercontent.com"
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

    init() {
        let defaults = UserDefaults.standard
        self.isAuthenticated = defaults.bool(forKey: accessKey)
        self.displayName = defaults.string(forKey: nameKey)
        self.userEmail = defaults.string(forKey: emailKey)
        self.newsletterEmail = defaults.string(forKey: newsletterEmailKey)
        self.newsletterOptIn = defaults.bool(forKey: newsletterOptInKey)

#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
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
                print("[Auth] Apple sign-in returned no email (likely re-auth). Consider capturing email on first consent.")
            }
        }
    }

    func signInWithGoogle(presenting viewController: UIViewController) async -> Result<Void, Error> {
#if canImport(GoogleSignIn)
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
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: accessKey)
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: emailKey)
        defaults.removeObject(forKey: newsletterEmailKey)
        defaults.removeObject(forKey: newsletterOptInKey)
        defaults.synchronize()
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
#endif
        isAuthenticated = false
        displayName = nil
        userEmail = nil
        newsletterEmail = nil
        newsletterOptIn = false
        print("[Auth] Signed out locally")
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
        defaults.synchronize()
    }

    func signInWithPassword(email: String, password: String) -> Result<Void, Error> {
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
    func completeSignIn(userID: String, name: String?, email: String?) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: accessKey)
        defaults.set(userID, forKey: userIDKey)
        if let name {
            defaults.set(name, forKey: nameKey)
        }
        if let email {
            defaults.set(email, forKey: emailKey)
        }
        defaults.synchronize()
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

    var errorDescription: String? {
        "Invalid email or password."
    }
}
