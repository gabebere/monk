import Foundation
import AuthenticationServices
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class AuthManager: ObservableObject {
    private let googleClientID = "767517007770-v4i7a49e9qi2b3tmgpgu7s1nrtmf9enb.apps.googleusercontent.com"

    @Published public private(set) var isAuthenticated: Bool
    @Published public private(set) var displayName: String?
    @Published public private(set) var userEmail: String?
    @Published public private(set) var newsletterEmail: String?
    @Published public private(set) var newsletterOptIn: Bool = false

    private let accessKey = "auth.isAuthenticated"
    private let userIDKey = "auth.userID"
    private let nameKey = "auth.name"
    private let emailKey = "auth.email"
    private let newsletterEmailKey = "auth.newsletterEmail"
    private let newsletterOptInKey = "auth.newsletterOptIn"

    public init() {
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

    public var currentUserId: String? {
        UserDefaults.standard.string(forKey: userIDKey)
    }

    public var currentUserEmail: String? {
        UserDefaults.standard.string(forKey: emailKey)
    }

    public func handleAppleAuthorization(_ authorization: ASAuthorization) {
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

    #if canImport(UIKit)
    public func signInWithGoogle(presenting viewController: UIViewController) async -> Result<Void, Error> {
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
    #else
    public func signInWithGoogle() async -> Result<Void, Error> {
        struct GoogleUnavailable: LocalizedError {
            var errorDescription: String? { "Google Sign-In is not available on this platform." }
        }
        return .failure(GoogleUnavailable())
    }
    #endif

    public func signOut() {
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

    public func applyNewsletterPreference(email: String?, optedIn: Bool) {
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
