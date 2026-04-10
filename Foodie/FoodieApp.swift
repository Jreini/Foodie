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
        }
    }
}
