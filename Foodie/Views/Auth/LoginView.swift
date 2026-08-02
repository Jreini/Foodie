import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

// First screen an unauthenticated user sees. Both providers are offered
// because App Store Guideline 4.8 requires Sign in with Apple wherever a
// third-party login like Google is available.
struct LoginView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()
                branding
                Spacer()
                signInButtons
                errorBanner
                finePrint
            }
            .padding(.horizontal, AppTheme.spacingXL)
            .padding(.bottom, AppTheme.spacingXL)
        }
    }

    // MARK: - Background

    // Warm wash of the app's accent, heaviest at the top so the branding sits
    // inside the color and the buttons stay on a near-neutral surface.
    private var background: some View {
        LinearGradient(
            colors: [
                AppTheme.primaryColor.opacity(colorScheme == .dark ? 0.35 : 0.28),
                AppTheme.screenBackground
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
        .background(AppTheme.screenBackground.ignoresSafeArea())
    }

    // MARK: - Branding

    private var branding: some View {
        VStack(spacing: AppTheme.spacingLG) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 84))
                .foregroundStyle(AppTheme.primaryGradient)
                .shadow(color: AppTheme.primaryColor.opacity(0.3), radius: 16, y: 6)

            VStack(spacing: AppTheme.spacingSM) {
                Text("Foodie")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Find your next favorite meal —\ntogether with friends.")
                    .font(.headline)
                    .fontWeight(.regular)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    // MARK: - Sign-in Buttons

    private var signInButtons: some View {
        VStack(spacing: AppTheme.spacingMD) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await auth.signInWithApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: buttonHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))

            // Google's own button, rather than a custom one, so the result stays
            // within their branding requirements.
            GoogleSignInButton(
                scheme: colorScheme == .dark ? .dark : .light,
                style: .wide
            ) {
                Task { await auth.signInWithGoogle() }
            }
            .frame(height: buttonHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))
        }
        .disabled(auth.isAuthenticating)
        .opacity(auth.isAuthenticating ? 0.5 : 1)
        .overlay {
            if auth.isAuthenticating {
                ProgressView().controlSize(.large)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isAuthenticating)
    }

    private var buttonHeight: CGFloat { 50 }

    // MARK: - Error

    @ViewBuilder
    private var errorBanner: some View {
        if let message = auth.errorMessage {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)
                .padding(.top, AppTheme.spacingLG)
                .transition(.opacity)
        }
    }

    // MARK: - Fine Print

    private var finePrint: some View {
        Text("We only use your account to identify you to your friends.")
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.top, AppTheme.spacingXL)
    }
}

#Preview {
    LoginView()
        .environment(AuthManager())
}
