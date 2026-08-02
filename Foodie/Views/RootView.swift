import SwiftUI

// Chooses what to show based on session state. Everything below `.ready` can
// assume both a signed-in user and a complete profile.
struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                // The keychain lookup and profile fetch are quick, so this is a
                // quiet placeholder rather than a spinner that would flicker.
                LaunchView()

            case .signedOut:
                LoginView()

            case .needsUsername(let user):
                UsernameSetupView(displayName: user.fullName)

            case .profileUnavailable:
                ProfileUnavailableView()

            case .ready:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.state)
    }
}

// Matches the login screen's mark so restoring a session doesn't flash a
// different-looking screen on the way into the app.
private struct LaunchView: View {
    var body: some View {
        ZStack {
            AppTheme.screenBackground.ignoresSafeArea()
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 84))
                .foregroundStyle(AppTheme.primaryGradient)
        }
    }
}

// The account is valid but its profile couldn't be read — almost always a
// dropped connection. Signing out would lose the session for no reason, so
// offer a retry instead.
private struct ProfileUnavailableView: View {
    @Environment(AuthManager.self) private var auth
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            AppTheme.screenBackground.ignoresSafeArea()

            VStack(spacing: AppTheme.spacingLG) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 52))
                    .foregroundStyle(AppTheme.textSecondary)

                Text("Couldn't load your profile")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                Button {
                    Task {
                        isRetrying = true
                        await auth.retryProfileLoad()
                        isRetrying = false
                    }
                } label: {
                    Group {
                        if isRetrying {
                            ProgressView().tint(.white)
                        } else {
                            Text("Try Again").fontWeight(.semibold)
                        }
                    }
                    .frame(width: 160, height: 46)
                    .background(AppTheme.primaryGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))
                }
                .disabled(isRetrying)

                Button("Sign Out") {
                    Task { await auth.signOut() }
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, AppTheme.spacingSM)
            }
            .padding(AppTheme.spacingXL)
            .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    RootView()
        .environment(AuthManager())
}
