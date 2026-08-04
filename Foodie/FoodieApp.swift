//
//  FoodieApp.swift
//  Foodie
//
//  Created by Justin Reini on 4/9/26.
//

import SwiftUI
import CoreData
import GoogleSignIn
import UIKit

@main
struct FoodieApp: App {
    let persistenceController = PersistenceController.shared

    // Push registration is the one thing SwiftUI has no hook for — see
    // `AppDelegate` below.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Owns the session for the app's lifetime; RootView switches on its state.
    @State private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                // Injected as well as being a singleton, so views read it from
                // the environment like every other dependency. The singleton is
                // for the notification delegate, which has no environment.
                .environment(PushRouter.shared)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                // Google's OAuth flow returns through the app's custom URL
                // scheme. Without this hand-off the sign-in never completes.
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}

// Exists for exactly one reason: APNs delivers the device token to a UIKit
// application-delegate callback, and SwiftUI has no equivalent. Everything else
// about notifications lives in `PushNotificationService`.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistration(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistrationFailure(error)
        }
    }
}
