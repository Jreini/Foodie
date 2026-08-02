import SwiftUI

// Chooses between the login screen and the app based on session state.
// Everything below this point can assume a signed-in user.
struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                // The keychain lookup is near-instant, so this is a quiet
                // placeholder rather than a spinner that would only flicker.
                LaunchView()
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.state)
    }
}

// Matches the login screen's mark so restoring a session doesn't flash a
// different-looking screen on the way to the app.
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

#Preview {
    RootView()
        .environment(AuthManager())
}
