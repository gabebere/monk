import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

public struct AuthGatewayView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var showingGoogleAlert = false
    @State private var googleError: String?

    public init() {}

    public var body: some View {
        ZStack {
            SignInBackground()

            VStack(spacing: 32) {
                Spacer(minLength: 20)

                    VStack(spacing: 18) {
                        LogoLockup()

                        VStack(spacing: 10) {
                            Text("Join Monk")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                        Text("A quiet place for focused time.")
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 260)
                    }
                }

                Spacer()

                VStack(spacing: 16) {
                    PressableContainer {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task {
                                switch result {
                                case .success(let authResult):
                                    auth.handleAppleAuthorization(authResult)
                                    Haptics.heavy()
                                case .failure:
                                    break
                                }
                            }
                        }
                        .signInWithAppleButtonStyle(.whiteOutline)
                        .frame(height: 56)
                        .frame(maxWidth: 340)
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.30), lineWidth: 1)
                        )
                    }

#if canImport(GoogleSignIn)
                    PressableContainer {
                        Button {
                            Task { await handleGoogleSignIn() }
                        } label: {
                            HStack(spacing: 12) {
                                GoogleBrandGlyph()
                                    .frame(width: 24, height: 24)
                                Text("Continue with Google")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.black.opacity(0.95))
                            }
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .frame(maxWidth: 340)
                    }
#else
                    Button {
                        showingGoogleAlert = true
                        googleError = "Google Sign-In is not available in this build."
                    } label: {
                        Text("Continue with Google")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.95))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .frame(maxWidth: 340)
#endif
                }

                VStack(spacing: 8) {
                    Text("No spam. No selling data. Ever.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
        }
        .preferredColorScheme(.dark)
        .alert("Google Sign-In", isPresented: $showingGoogleAlert) {
            Button("OK", role: .cancel) { showingGoogleAlert = false }
        } message: {
            Text(googleError ?? "Sign in with Google is not available in this build.")
        }
    }

    #if canImport(UIKit)
    private func handleGoogleSignIn() async {
        guard let controller = topViewController() else {
            googleError = "Unable to start Google sign-in."
            showingGoogleAlert = true
            return
        }
        let result = await auth.signInWithGoogle(presenting: controller)
        switch result {
        case .success:
            Haptics.heavy()
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
    #else
    private func handleGoogleSignIn() async {
        let result = await auth.signInWithGoogle()
        switch result {
        case .success:
            Haptics.heavy()
            showingGoogleAlert = false
            googleError = nil
        case .failure(let error):
            googleError = error.localizedDescription.isEmpty
            ? "Sign in with Google failed. Ensure the GoogleSignIn SDK is linked and configured."
            : error.localizedDescription
            showingGoogleAlert = true
        }
    }
    #endif
}

// MARK: - Components

private struct SignInBackground: View {
    @State private var drift = false

    var body: some View {
        GeometryReader { _ in
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.11, green: 0.09, blue: 0.25), location: 0.0),   // #1D1840
                    .init(color: Color(red: 0.12, green: 0.17, blue: 0.42), location: 0.38), // #1E2B6A
                    .init(color: Color(red: 0.13, green: 0.47, blue: 0.64), location: 1.0)   // #2279A3
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .overlay(
                Circle()
                    .fill(Color(red: 0.22, green: 0.84, blue: 0.95).opacity(0.20)) // #37D5F3 @ 0.20
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(x: 0, y: drift ? -6 : 10)
                    .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: drift)
            )
            .onAppear { drift = true }
        }
    }
}

private struct LogoLockup: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 150, height: 150)
                .blur(radius: 28)

            Image("MonkLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        }
    }
}

private struct PressableContainer<Content: View>: View {
    @GestureState private var isPressed = false
    @State private var didHaptic = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onChanged { _ in
                        if !didHaptic {
                            Haptics.medium()
                            didHaptic = true
                        }
                    }
                    .onEnded { _ in
                        didHaptic = false
                    }
            )
    }
}

#if canImport(GoogleSignIn)
private struct GoogleBrandGlyph: View {
    private var logoImage: Image {
        if UIImage(named: "googlelogo") != nil {
            return Image("googlelogo")
        }
        if let asset = UIImage(named: "googlelogo") {
            return Image(uiImage: asset)
        }
        if let bundle = Bundle(for: GIDSignInButton.self) as Bundle? {
            let candidates = [
                "ic_google_logo",
                "google_logo",
                "googleg_standard_color_24dp",
                "googleg_standard_color_18dp",
                "ic_google_g_logo"
            ]
            for name in candidates {
                if let image = UIImage(named: name, in: bundle, with: nil) {
                    return Image(uiImage: image)
                }
            }
        }
        return Image(systemName: "g.circle.fill")
    }

    var body: some View {
        logoImage
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
    }
}
#endif
