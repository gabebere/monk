import SwiftUI
import AuthenticationServices
import UIKit

struct AuthGatewayView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var showingGoogleAlert = false
    @State private var googleError: String?

    var body: some View {
        ZStack {
            AnimatingBackground(base: Theme.settingsBackground(), halo: Theme.haloGradient)
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 12) {
                    Image("MonkLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
                    Text("Welcome to Monk")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Sign in to keep your focus data synced across devices.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            switch result {
                            case .success(let authResult):
                                auth.handleAppleAuthorization(authResult)
                            case .failure:
                                break
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        Task { await handleGoogleSignIn() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                            Text("Sign in with Google")
                                .font(.headline)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .preferredColorScheme(.dark)
        .alert("Google Sign-In", isPresented: $showingGoogleAlert) {
            Button("OK", role: .cancel) { showingGoogleAlert = false }
        } message: {
            Text(googleError ?? "Sign in with Google is not available in this build.")
        }
    }

    private func handleGoogleSignIn() async {
        guard let controller = topViewController() else {
            googleError = "Unable to start Google sign-in."
            showingGoogleAlert = true
            return
        }
        let result = await auth.signInWithGoogle(presenting: controller)
        switch result {
        case .success:
            showingGoogleAlert = false
            googleError = nil
        case .failure(let error):
            googleError = error.localizedDescription.isEmpty
            ? "Sign in with Google failed. Ensure the GoogleSignIn SDK is linked, client ID is configured, and the URL scheme is set."
            : error.localizedDescription
            showingGoogleAlert = true
        }
    }

    private func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
