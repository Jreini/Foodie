import Foundation
import SwiftUI
import Observation

@Observable
class BucketListViewModel {
    var entries: [BucketListEntry] = []
    var restaurants: [UUID: Restaurant] = [:]
    var randomPick: Restaurant? = nil

    private let dataService: DataServiceProtocol

    init(dataService: DataServiceProtocol = MockDataService()) {
        self.dataService = dataService
    }

    func loadBucketList() {
        let currentUser = dataService.fetchCurrentUser()
        entries = dataService.fetchBucketList(for: currentUser.id)

        // Map restaurant IDs to Restaurant objects for easy lookup
        let allRestaurants = dataService.fetchAllRestaurants()
        restaurants = Dictionary(uniqueKeysWithValues: allRestaurants.map { ($0.id, $0) })
    }

    func restaurantForEntry(_ entry: BucketListEntry) -> Restaurant? {
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
}
