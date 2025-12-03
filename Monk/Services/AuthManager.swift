import Foundation
import AuthenticationServices
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class AuthManager: ObservableObject {
    private let googleClientID = "767517007770-v4i7a49e9qi2b3tmgpgu7s1nrtmf9enb.apps.googleusercontent.com"

@Published private(set) var isAuthenticated: Bool
@Published private(set) var displayName: String?
@Published private(set) var userEmail: String?

private let accessKey = "auth.isAuthenticated"
private let userIDKey = "auth.userID"
private let nameKey = "auth.name"
private let emailKey = "auth.email"

    init() {
        let defaults = UserDefaults.standard
        self.isAuthenticated = defaults.bool(forKey: accessKey)
        self.displayName = defaults.string(forKey: nameKey)
        self.userEmail = defaults.string(forKey: emailKey)

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
        defaults.synchronize()
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
#endif
        isAuthenticated = false
        displayName = nil
        userEmail = nil
        print("[Auth] Signed out locally")
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
