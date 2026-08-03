import Foundation
import Observation
import Supabase
import AuthenticationServices
import GoogleSignIn
import UIKit

// Owns the signed-in session for the whole app.
//
// The Supabase SDK already persists sessions in the keychain and refreshes
// tokens on its own, so this type's job is narrow: mirror that into one value
// the UI can switch on, and drive the two native sign-in flows.
@MainActor
@Observable
final class AuthManager {

    // MARK: - State

    // `.loading` covers the brief window at launch while the SDK restores a
    // stored session, so the login screen never flashes for a signed-in user.
    enum State: Equatable {
        case loading
        case signedOut
        // Authenticated, but the account hasn't claimed a username yet.
        case needsUsername(AuthenticatedUser)
        // Authenticated with a complete profile — the only state the app proper
        // is reachable from.
        case ready(AuthenticatedUser, Profile)
        // Authenticated, but the profile row couldn't be read (offline, or the
        // schema migration hasn't been applied). Recoverable, so this doesn't
        // dump the user back to the login screen.
        case profileUnavailable(AuthenticatedUser)
    }

    // The slice of the Supabase user this app actually needs. Owning the type
    // keeps the SDK out of the views, and lets Phase 2's profiles table extend
    // it without the UI changing.
    struct AuthenticatedUser: Equatable {
        let id: UUID
        let email: String?
        let fullName: String?
    }

    private(set) var state: State = .loading

    // Shown on the login screen when an attempt fails. Cancelling a sign-in
    // sheet is a normal thing to do, not a failure, and never sets this.
    var errorMessage: String?

    // Disables the sign-in buttons while a round trip is in flight.
    private(set) var isAuthenticating = false

    private var stateObservationTask: Task<Void, Never>?

    init() {
        observeAuthState()
    }

    // MARK: - Session Observation

    // `authStateChanges` always emits `.initialSession` first — that is what
    // moves us out of `.loading`, whether or not a stored session was found.
    private func observeAuthState() {
        stateObservationTask = Task { [weak self] in
            for await (event, session) in SupabaseService.client.auth.authStateChanges {
                guard let self else { return }
                self.apply(event: event, session: session)
            }
        }
    }

    private func apply(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            guard let session else {
                state = .signedOut
                return
            }

            let user = Self.authenticatedUser(from: session)
            // Token refreshes fire on a timer. Re-fetching the profile each
            // time would flicker the UI for no benefit.
            guard !isResolved(for: user) else { return }

            state = .loading
            Task { await loadProfile(for: user) }

        case .signedOut:
            state = .signedOut

        default:
            break
        }
    }

    private func isResolved(for user: AuthenticatedUser) -> Bool {
        switch state {
        case .ready(let current, _):      return current.id == user.id
        case .needsUsername(let current): return current.id == user.id
        default:                          return false
        }
    }

    // MARK: - Profile

    // Convenience for views that only care about the profile itself.
    var profile: Profile? {
        if case .ready(_, let profile) = state { return profile }
        return nil
    }

    private func loadProfile(for user: AuthenticatedUser) async {
        do {
            let profile = try await ProfileService.fetchProfile(id: user.id)

            // A row with no username means the account exists but onboarding
            // never finished. A missing row means the signup trigger hasn't run
            // — either way the next step is picking a username.
            if let profile, profile.username != nil {
                state = .ready(user, profile)
            } else {
                state = .needsUsername(user)
            }
        } catch {
            state = .profileUnavailable(user)
        }
    }

    // Claims a username and completes onboarding. Throws so the setup screen
    // can distinguish "taken" from a general failure.
    func claimUsername(_ username: String) async throws {
        guard case .needsUsername(let user) = state else { return }

        do {
            let profile = try await ProfileService.claimUsername(
                username,
                userId: user.id,
                name: user.fullName
            )
            state = .ready(user, profile)
        } catch where ProfileService.isUniqueViolation(error) {
            // Someone claimed it between the availability check and the write.
            throw UsernameTakenError()
        }
    }

    func updateProfile(name: String?, bio: String) async throws {
        guard case .ready(let user, _) = state else { return }
        let profile = try await ProfileService.updateProfile(id: user.id, name: name, bio: bio)
        state = .ready(user, profile)
    }

    // Points the profile at a freshly uploaded avatar, or clears it with nil.
    // Returns the path that was replaced so the caller can delete the old file —
    // storage doesn't cascade, and nothing else knows the previous path once
    // this returns.
    @discardableResult
    func updateAvatar(path: String?) async throws -> String? {
        guard case .ready(let user, let existing) = state else { return nil }
        let profile = try await ProfileService.updateAvatar(id: user.id, path: path)
        state = .ready(user, profile)
        return existing.avatarPath
    }

    func retryProfileLoad() async {
        guard case .profileUnavailable(let user) = state else { return }
        state = .loading
        await loadProfile(for: user)
    }

    private static func authenticatedUser(from session: Session) -> AuthenticatedUser {
        let user = session.user
        // Apple lands the name under `full_name` (we write it there below);
        // Google populates `name` itself.
        let name = user.userMetadata["full_name"]?.stringValue
            ?? user.userMetadata["name"]?.stringValue
        return AuthenticatedUser(id: user.id, email: user.email, fullName: name)
    }

    // MARK: - Sign in with Apple

    // Called from `SignInWithAppleButton`'s completion handler.
    func signInWithApple(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let authorization = try result.get()

            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                throw SignInFailure.missingAppleIdentityToken
            }

            try await SupabaseService.client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken)
            )

            // Apple sends the user's name on the FIRST authorization only. If we
            // don't persist it now it is gone for good, short of the user
            // revoking the app under Settings > Apple Account > Sign in with
            // Apple. Google, by contrast, returns it on every sign-in.
            if let name = Self.formattedName(from: credential.fullName) {
                try await storeFullName(name)
            }
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // User dismissed the sheet — nothing to report.
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    private func storeFullName(_ name: String) async throws {
        _ = try await SupabaseService.client.auth.update(
            user: UserAttributes(data: ["full_name": .string(name)])
        )
    }

    private static func formattedName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return name.isEmpty ? nil : name
    }

    // MARK: - Sign in with Google

    func signInWithGoogle() async {
        errorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            guard let presenter = Self.presentingViewController() else {
                throw SignInFailure.noPresenter
            }

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)

            guard let idToken = result.user.idToken?.tokenString else {
                throw SignInFailure.missingGoogleIdentityToken
            }

            try await SupabaseService.client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
            )
        } catch let error as NSError
            where error.domain == kGIDSignInErrorDomain && error.code == Self.googleCanceledCode {
            // User dismissed the Google sheet.
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // `kGIDSignInErrorCodeCanceled`. Spelled out rather than referenced so this
    // doesn't depend on how the ObjC error enum bridges into Swift.
    private static let googleCanceledCode = -5

    // Google's sheet needs a UIKit presenter, which SwiftUI doesn't hand us.
    private static func presentingViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    // MARK: - Sign Out

    func signOut() async {
        errorMessage = nil
        do {
            try await SupabaseService.client.auth.signOut()
            // Clears Google's cached account so the next sign-in shows the
            // picker instead of silently reusing the last account.
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - Errors

    enum SignInFailure: LocalizedError {
        case missingAppleIdentityToken
        case missingGoogleIdentityToken
        case noPresenter

        var errorDescription: String? {
            switch self {
            case .missingAppleIdentityToken:
                return "Apple didn't return a sign-in token. Please try again."
            case .missingGoogleIdentityToken:
                return "Google didn't return a sign-in token. Please try again."
            case .noPresenter:
                return "Couldn't open the Google sign-in screen. Please try again."
            }
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let failure = error as? SignInFailure {
            return failure.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You appear to be offline. Check your connection and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                break
            }
        }
        return "Sign-in failed. Please try again."
    }
}
