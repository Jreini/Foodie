import Foundation
import SwiftUI
import Observation

@Observable
class TastingListViewModel {
    var entries: [TastingListEntry] = []
    var restaurants: [UUID: Restaurant] = [:]
    var randomPick: Restaurant? = nil

    private let dataService: DataServiceProtocol
    private var currentUserId: UUID?

    init(dataService: DataServiceProtocol = MockDataService()) {
        self.dataService = dataService
    }

    func loadTastingList() {
        let currentUser = dataService.fetchCurrentUser()
        currentUserId = currentUser.id
        entries = dataService.fetchTastingList(for: currentUser.id)

        // Map restaurant IDs to Restaurant objects for easy lookup
        let allRestaurants = dataService.fetchAllRestaurants()
        restaurants = Dictionary(uniqueKeysWithValues: allRestaurants.map { ($0.id, $0) })
    }

    func restaurantForEntry(_ entry: TastingListEntry) -> Restaurant? {
        restaurants[entry.restaurantId]
    }

    func removeEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    func pickRandomEntry() {
        guard !entries.isEmpty else { return }
        if let entry = entries.randomElement() {
            randomPick = restaurants[entry.restaurantId]
        }
    }

    // Restaurants not yet on the Tasting List, for the picker sheet
    var availableRestaurants: [Restaurant] {
        let existingIds = Set(entries.map { $0.restaurantId })
        return restaurants.values
            .filter { !existingIds.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    // Adds a restaurant to the Tasting List (local-only for mock data)
    func addRestaurant(_ restaurant: Restaurant, notes: String = "") {
        guard let userId = currentUserId else { return }
        // Prevent duplicates
        guard !entries.contains(where: { $0.restaurantId == restaurant.id }) else { return }
        let entry = TastingListEntry(
            id: UUID(),
            userId: userId,
            restaurantId: restaurant.id,
            dateAdded: Date(),
            notes: notes
        )
        entries.insert(entry, at: 0)
    }
}
