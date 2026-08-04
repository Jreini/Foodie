import Foundation
import UIKit
import UserNotifications

// Owns everything the device side of push needs: asking for the permission,
// handing the APNs token to the database, and reacting when one is tapped.
//
// Deliberately not part of `AuthManager`. Permission is asked for once the user
// is signed in and inside the app — not while the login screen is up, where a
// system prompt would be asking about notifications for an account that doesn't
// exist yet.
@MainActor
final class PushNotificationService {
    static let shared = PushNotificationService()

    // `UNUserNotificationCenter.delegate` is a weak reference. Held here for the
    // app's lifetime because nothing else would keep it alive, and a deallocated
    // delegate means taps silently stop working.
    private let delegate = Delegate()

    // The token this launch registered, kept so sign-out can remove exactly it.
    private var registeredToken: String?

    private let dataService: any DataServiceProtocol

    private init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    // MARK: - Registration

    // Called once the app reaches its signed-in state.
    //
    // Safe to call repeatedly: APNs tokens can be reissued (restores, some OS
    // updates), so re-registering on every launch is how the stored one stays
    // current — not a wasted call.
    func start() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate

        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            let granted = try? await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            guard granted == true else { return }
            UIApplication.shared.registerForRemoteNotifications()

        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()

        case .denied:
            // Nothing to do, and nothing to nag about — iOS only lets an app ask
            // once, so the only way back is Settings.
            break

        @unknown default:
            break
        }
    }

    // Apple hands back the token as raw bytes; APNs addresses devices by its hex
    // string.
    func handleRegistration(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        registeredToken = hex

        Task {
            do {
                try await dataService.registerDeviceToken(hex, isSandbox: Self.usesSandboxAPNs)
            } catch {
                // Losing a registration costs notifications, not correctness,
                // and the next launch tries again.
                #if DEBUG
                print("[Foodie] couldn't register device token: \(error)")
                #endif
            }
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        // Routine in the Simulator, which has no APNs connection at all.
        #if DEBUG
        print("[Foodie] remote notification registration failed: \(error)")
        #endif
    }

    // Detaches this device from the account that is leaving, so the next person
    // to sign in on this phone doesn't receive their notifications.
    //
    // Best effort. The database also defends against this: `device_tokens` is
    // keyed by the token itself, so signing in re-claims the row for the new
    // account even if this call never happened.
    func unregisterCurrentToken() async {
        guard let token = registeredToken else { return }
        registeredToken = nil
        try? await dataService.unregisterDeviceToken(token)
    }

    // Debug builds get tokens the APNs sandbox accepts; TestFlight and the App
    // Store get production ones. The same string is rejected by the wrong host,
    // which is why it's stored alongside the token.
    //
    // This is a build-configuration guess, not a fact — a Release build run from
    // Xcode is still a sandbox device. The server treats it as a hint and
    // corrects itself if the other host turns out to be the right one.
    private static var usesSandboxAPNs: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    // MARK: - Delegate

    // A separate object, matching how `CameraPicker` handles its UIKit
    // delegates: it keeps the isolation question simple and leaves this type
    // free to be main-actor state.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {

        // Without this, a notification that arrives while the app is open is
        // delivered silently — which reads as broken to someone sitting on the
        // Feed waiting for a friend to accept.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound, .list]
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            let userInfo = response.notification.request.content.userInfo
            await MainActor.run {
                PushRouter.shared.route(fromPushPayload: userInfo)
            }
        }
    }
}
