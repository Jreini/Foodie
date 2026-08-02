//
//  FoodieApp.swift
//  Foodie
//
//  Created by Justin Reini on 4/9/26.
//

import SwiftUI
import CoreData

@main
struct FoodieApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task { await printSupabaseSetupCheck() }
        }
    }

    // Phase 0 wiring check — prints Supabase connectivity to the Xcode console
    // on launch. Remove once Phase 1 auth replaces it.
    private func printSupabaseSetupCheck() async {
        #if DEBUG
        print("[Foodie] Supabase: \(await SupabaseService.healthCheck())")
        #endif
    }
}
