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
            VStack(spacing: 26) {
                VStack(spacing: 14) {
                    Image("MonkLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
                    Text("Enter Monk")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Sign in to keep your focus, purchases, and preferences synced.")
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
                .padding(.top, 52)

                VStack(spacing: 16) {
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
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                    )

                    Button {
                        Task { await handleGoogleSignIn() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.black)
                            Text("Continue with Google")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
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
