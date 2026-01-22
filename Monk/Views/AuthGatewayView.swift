import SwiftUI
import AuthenticationServices
import UIKit

struct AuthGatewayView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var showingGoogleAlert = false
    @State private var googleError: String?
    @State private var email = ""
    @State private var password = ""
    @State private var passwordError: String?
    @State private var passwordBusy = false
    @State private var showingEmailSheet = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AnimatingBackground() // matches the Home screen gradient/halo

                VStack(spacing: 0) {
                    Spacer(minLength: proxy.safeAreaInsets.top + proxy.size.height * 0.14)

                    VStack(spacing: 14) {
                        Image("MonkLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
                    }
                    .frame(maxWidth: 520)

                    Spacer(minLength: 32)

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
                                Image("googlelogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
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

                        Button {
                            showingEmailSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 16)
                                Text("Continue with Monk email")
                                    .font(.headline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 520)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom + 24, 32))
            }
        }
        .preferredColorScheme(.dark)
        .alert("Google Sign-In", isPresented: $showingGoogleAlert) {
            Button("OK", role: .cancel) { showingGoogleAlert = false }
        } message: {
            Text(googleError ?? "Sign in with Google is not available in this build.")
        }
        .sheet(isPresented: $showingEmailSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sign in with your Monk email")
                        .font(.title2.weight(.bold))
                        .padding(.bottom, 6)

                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let passwordError {
                        Text(passwordError)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    Button {
                        Task { await handlePasswordSignIn() }
                    } label: {
                        HStack {
                            if passwordBusy {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Sign in")
                                .font(.headline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(email.isEmpty || password.isEmpty || passwordBusy)

                    Spacer()
                }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingEmailSheet = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
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

    private func handlePasswordSignIn() async {
        await MainActor.run { passwordBusy = true }
        let result = auth.signInWithPassword(email: email, password: password)
        await MainActor.run {
            passwordBusy = false
            switch result {
            case .success:
                passwordError = nil
                showingEmailSheet = false
            case .failure(let error):
                passwordError = error.localizedDescription
            }
        }
    }
}
