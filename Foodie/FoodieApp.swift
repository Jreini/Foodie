//
//  FoodieApp.swift
//  Foodie
//
//  Created by Justin Reini on 4/9/26.
//

import SwiftUI
import CoreData
import GoogleSignIn

@main
struct FoodieApp: App {
    let persistenceController = PersistenceController.shared

    // Owns the session for the app's lifetime; RootView switches on its state.
    @State private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                // Google's OAuth flow returns through the app's custom URL
                // scheme. Without this hand-off the sign-in never completes.
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
